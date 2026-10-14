# WHOOP MCP

Read-only access to your WHOOP data (recovery, sleep, strain, workouts) for Claude.
This server has OAuth built in, so it can be a claude.ai custom connector without an extra auth proxy.

| | |
|---|---|
| Upstream | [yuridivonis/whoop-mcp-server](https://github.com/yuridivonis/whoop-mcp-server) |
| Image | `ghcr.io/yuridivonis/whoop-mcp-server:1.5.1` |
| Port | 3000, Streamable HTTP at `/mcp` |
| Auth | Built-in OAuth, login with `MCP_AUTH_PASSWORD` |
| Reachable | Public (`whoop.example.com`) |

## Setup

1. Create an app at [developer.whoop.com](https://developer.whoop.com). Redirect URI: `https://whoop.example.com/callback`. Copy client ID and secret into `.env`.
2. LXC with Docker, fixed IP (example `192.168.1.24`).
3. In `/opt/mcp-whoop`:

   ```bash
   cp .env.example .env && chmod 600 .env && nano .env
   docker compose up -d
   ```

4. Firewall: [../common/mcp-firewall.service](../common/mcp-firewall.service) with `MCP_PORTS=3000`.
5. Public DNS record for `whoop.example.com`, port 443 forwarded to Caddy, and the `whoop.example.com` block from [../common/Caddyfile.snippets](../common/Caddyfile.snippets).
6. claude.ai: Customize > Connectors > + Add > Add custom connector, URL `https://whoop.example.com/mcp`, then log in with `MCP_AUTH_PASSWORD` and connect your WHOOP account.
7. Claude Code: `claude mcp add --transport http --scope user whoop https://whoop.example.com/mcp`, then `/mcp` to log in.

`TRUST_PROXY=1` tells the server there is exactly one proxy (Caddy) in front, so it reads the right client IP and scheme.

The Caddy block in this repo limits `/mcp` to Anthropic's outbound range plus LAN and Tailscale. That allow list is our suggestion on top of the built-in OAuth. Drop the private ranges if only claude.ai should reach it.
