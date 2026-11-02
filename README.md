# Atlas Intelligence MCP bridge

The Atlas Intelligence MCP bridge connects your MCP client to Atlas Intelligence. It is a local stdio MCP server that
signs you in with your Microsoft Entra ID account and forwards every tool to the hosted Atlas Intelligence MCP. The tools
you see are the ones your role permits.

## Requirements

- Windows x64.
- [Claude Code](https://claude.com/claude-code) with `claude` on the `PATH`, or another MCP client.
- An account registered in Atlas Intelligence.

## Install

Run this command in Windows PowerShell 5.1 or PowerShell 7, replacing each placeholder with the value your organization
gives you for Atlas Intelligence:

```powershell
& ([scriptblock]::Create((irm https://github.com/Atlas-Enterprise-Software/atlas-intelligence-mcp/releases/latest/download/install.ps1))) `
    -Name <server name> `
    -ServerUrl <hosted MCP URL> `
    -TenantId <tenant id> `
    -ClientId <client id>
```

`-Name` is the name the MCP server is registered under. Use the name your MCP server already has, so the bridge replaces
it instead of being added beside it.

The command downloads the latest release, checks it against its published SHA-256 and installs it. Run the same command
again to update the bridge.

When `claude` is on the `PATH`, the command registers the bridge in Claude Code. Otherwise it prints the `mcpServers`
block to paste into the configuration of your MCP client.

## First sign-in

The first time your MCP client lists or calls a tool, the bridge opens the Windows account picker. Choose the account you
use for Atlas Intelligence. Later sessions sign in silently.

To check the server in Claude Code, run `/mcp` and confirm that the server is connected.

## Troubleshooting

- **"has no access to Atlas Intelligence in this environment"**: the account you signed in with is not registered in
  Atlas Intelligence, or the tenant id and client id do not belong to the same environment as the hosted MCP URL. Check
  that you chose the right account and run the install command again with the values for your environment.
- **A redirect URI or public client error at sign-in** (an `AADSTS` error): the Atlas Intelligence app registration of
  your organization is not set up for signing in from the bridge. Ask the administrator of Atlas Intelligence to review
  it.
- **The executable is in use**: the installer cannot replace the bridge while an MCP client runs it. Close the MCP
  clients that use the bridge, for example by exiting Claude Code, and run the install command again.

## Where it is installed

The executable is installed to `%LOCALAPPDATA%\Programs\AtlasIntelligenceMcp\atlas-intelligence-mcp.exe`.

## Uninstall

1. Remove the server from Claude Code:

   ```powershell
   claude mcp remove <server name> -s user
   ```

   With another MCP client, delete the server from its configuration.

2. Delete the folder `%LOCALAPPDATA%\Programs\AtlasIntelligenceMcp`.

## Third-party notices

The bridge is a self-contained executable that includes third-party components. Their notices are in
[THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt).
