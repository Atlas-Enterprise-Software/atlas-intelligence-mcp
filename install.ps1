<#
.SYNOPSIS
Installs or updates the Atlas Intelligence MCP bridge and registers it in Claude Code.

.DESCRIPTION
Downloads the latest atlas-intelligence-mcp.exe released on GitHub, verifies its SHA-256 and installs it to
%LOCALAPPDATA%\Programs\AtlasIntelligenceMcp, replacing a previous version. When the claude command is on the PATH,
the bridge is registered as a user-scoped stdio MCP server with the given settings; otherwise the equivalent
mcpServers JSON block is printed to paste into the MCP client's configuration. Running it again updates the
executable and the registration. Runs on Windows PowerShell 5.1 and PowerShell 7.

.PARAMETER ServerUrl
Absolute https URL of the hosted Atlas Intelligence MCP the bridge forwards every tool to.

.PARAMETER TenantId
Directory (tenant) id of the Atlas Intelligence app registration.

.PARAMETER ClientId
Client id of the Atlas Intelligence app registration of the same environment as ServerUrl.

.PARAMETER Name
Name the MCP server is registered under. Defaults to atlas-intelligence.

.EXAMPLE
& ([scriptblock]::Create((irm https://github.com/Atlas-Enterprise-Software/atlas-intelligence-mcp/releases/latest/download/install.ps1))) -ServerUrl <hosted MCP URL> -TenantId <tenant id> -ClientId <client id>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ServerUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $TenantId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ClientId,

    [ValidateNotNullOrEmpty()]
    [string] $Name = 'atlas-intelligence'
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 renders the download progress bar so slowly that it dominates the download time.
$ProgressPreference = 'SilentlyContinue'

$ExecutableName = 'atlas-intelligence-mcp.exe'
$HashFileExtension = '.sha256'
$LatestReleaseDownloadUrl = 'https://github.com/Atlas-Enterprise-Software/atlas-intelligence-mcp/releases/latest/download'
$InstallDirectory = Join-Path $env:LOCALAPPDATA 'Programs\AtlasIntelligenceMcp'
$ClaudeScope = 'user'
# npm installs claude beside an extensionless shell script and a .ps1 wrapper, which PowerShell cannot run as an application.
$RunnableExtensions = @('.exe', '.cmd', '.bat')
$BatchExtensions = @('.cmd', '.bat')
# cmd.exe interprets these characters in the arguments PowerShell passes to a .cmd or .bat shim.
$CmdMetacharacters = '[&|<>^%!"]'

function Enable-Tls12 {
    # Windows PowerShell 5.1 may still default to protocols GitHub refuses.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Save-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)] [string] $AssetName,
        [Parameter(Mandatory = $true)] [string] $DestinationDirectory
    )

    $destination = Join-Path $DestinationDirectory $AssetName
    Write-Host "Downloading $AssetName..."
    Invoke-WebRequest -Uri "$LatestReleaseDownloadUrl/$AssetName" -OutFile $destination -UseBasicParsing
    return $destination
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath,
        [Parameter(Mandatory = $true)] [string] $HashFilePath
    )

    $expectedHash = ([string](Get-Content -LiteralPath $HashFilePath -Raw)).Trim() -split '\s+' | Select-Object -First 1
    $actualHash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        throw "The SHA-256 of the downloaded $ExecutableName ($($actualHash.ToLowerInvariant())) differs from the published one ($expectedHash). Nothing was installed; run the script again, and report it if the hash still differs."
    }
}

function Test-FileInUse {
    param([Parameter(Mandatory = $true)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $stream.Dispose()
        return $false
    }
    catch [System.IO.IOException] {
        return $true
    }
}

function Install-Executable {
    param([Parameter(Mandatory = $true)] [string] $SourcePath)

    $target = Join-Path $InstallDirectory $ExecutableName
    if (Test-FileInUse -Path $target) {
        throw "$target is in use, so it cannot be replaced. Close the MCP clients that run the bridge (Claude Code, Claude Desktop, VS Code...) and run this script again."
    }

    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    Copy-Item -LiteralPath $SourcePath -Destination $target -Force
    Write-Host "Installed $target"
    return $target
}

function Get-BridgeEnvironment {
    return [ordered]@{
        Bridge__ServerUrl = $ServerUrl
        Bridge__TenantId  = $TenantId
        Bridge__ClientId  = $ClientId
    }
}

function Find-ClaudeCommand {
    return Get-Command -Name 'claude' -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $RunnableExtensions -contains $_.Extension } |
        Select-Object -First 1
}

function Invoke-Claude {
    param(
        [Parameter(Mandatory = $true)] [string] $ClaudePath,
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [switch] $Quiet
    )

    # Windows PowerShell 5.1 turns a native command's redirected standard error into a terminating error under 'Stop'.
    $ErrorActionPreference = 'Continue'
    if ($Quiet) {
        & $ClaudePath @Arguments *> $null
    }
    else {
        & $ClaudePath @Arguments | Out-Host
    }
    return $LASTEXITCODE
}

function Register-InClaudeCode {
    param(
        [Parameter(Mandatory = $true)] [string] $ClaudePath,
        [Parameter(Mandatory = $true)] [string] $ExecutablePath
    )

    # A missing server is the expected case on the first install, so the outcome of the removal is not checked.
    Invoke-Claude -ClaudePath $ClaudePath -Arguments @('mcp', 'remove', $Name, '-s', $ClaudeScope) -Quiet | Out-Null

    $addArguments = @('mcp', 'add', '--transport', 'stdio', $Name, '--scope', $ClaudeScope)
    $bridgeEnvironment = Get-BridgeEnvironment
    foreach ($key in $bridgeEnvironment.Keys) {
        $addArguments += @('-e', "$key=$($bridgeEnvironment[$key])")
    }
    $addArguments += @('--', $ExecutablePath)

    $exitCode = Invoke-Claude -ClaudePath $ClaudePath -Arguments $addArguments
    if ($exitCode -ne 0) {
        throw "claude mcp add failed with exit code $exitCode; the bridge is installed at $ExecutablePath but not registered, and any previous registration of '$Name' was removed. Run this script again to register it."
    }

    Write-Host "Registered the MCP server '$Name' in Claude Code (user scope). Run '/mcp' in Claude Code to check that it is connected."
}

function Test-PassableToClaude {
    param(
        [Parameter(Mandatory = $true)] [System.Management.Automation.ApplicationInfo] $Claude,
        [Parameter(Mandatory = $true)] [string] $ExecutablePath
    )

    if ($BatchExtensions -notcontains $Claude.Extension) {
        return $true
    }

    $values = @($ExecutablePath) + @((Get-BridgeEnvironment).Values)
    return $null -eq ($values | Where-Object { $_ -match $CmdMetacharacters } | Select-Object -First 1)
}

function Write-McpServersConfiguration {
    param(
        [Parameter(Mandatory = $true)] [string] $ExecutablePath,
        [Parameter(Mandatory = $true)] [string] $Reason
    )

    $configuration = [ordered]@{
        mcpServers = [ordered]@{
            $Name = [ordered]@{
                type    = 'stdio'
                command = $ExecutablePath
                args    = @()
                env     = Get-BridgeEnvironment
            }
        }
    }

    Write-Host "$Reason Add this block to the configuration of your MCP client:"
    Write-Host ($configuration | ConvertTo-Json -Depth 5)
}

Enable-Tls12

$downloadDirectory = Join-Path ([IO.Path]::GetTempPath()) ('atlas-intelligence-mcp-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $downloadDirectory | Out-Null
try {
    $downloadedExecutable = Save-ReleaseAsset -AssetName $ExecutableName -DestinationDirectory $downloadDirectory
    $downloadedHashFile = Save-ReleaseAsset -AssetName ($ExecutableName + $HashFileExtension) -DestinationDirectory $downloadDirectory
    Assert-FileHash -FilePath $downloadedExecutable -HashFilePath $downloadedHashFile
    $installedExecutable = Install-Executable -SourcePath $downloadedExecutable
}
finally {
    Remove-Item -LiteralPath $downloadDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

$claude = Find-ClaudeCommand
if ($null -eq $claude) {
    Write-McpServersConfiguration -ExecutablePath $installedExecutable -Reason 'The claude command is not on the PATH.'
}
elseif (-not (Test-PassableToClaude -Claude $claude -ExecutablePath $installedExecutable)) {
    $reason = "$($claude.Source) runs through cmd.exe, which would alter a value holding one of the characters & | < > ^ % ! "", " +
        'so the bridge was not registered and its previous registration, if any, was kept.'
    Write-McpServersConfiguration -ExecutablePath $installedExecutable -Reason $reason
}
else {
    Register-InClaudeCode -ClaudePath $claude.Source -ExecutablePath $installedExecutable
}
