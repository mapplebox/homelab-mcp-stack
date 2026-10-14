# Adding the servers to Claude Code

Every internal server is a Streamable HTTP endpoint at `/mcp` behind Caddy, with a Bearer token.
Caddy checks the token, except for Proxmox: ProxmoxMCP-Plus checks its `MCP_API_KEY` itself.
`--scope user` makes a server available in all your projects; Claude Code stores it in `~/.claude.json`.

```bash
claude mcp add --transport http --scope user calendar \
  https://mcp-cal.int.example.com/mcp \
  --header "Authorization: Bearer <token-from-openssl>"

claude mcp add --transport http --scope user proxmox \
  https://mcp-proxmox.int.example.com/mcp \
  --header "Authorization: Bearer <your-long-random-value>"

claude mcp add --transport http --scope user unifi \
  https://mcp-unifi.int.example.com/mcp \
  --header "Authorization: Bearer <unifi-token-from-openssl>"

claude mcp add --transport http --scope user paperless \
  https://mcp-paperless.int.example.com/mcp \
  --header "Authorization: Bearer <paperless-token-from-openssl>"
```

WHOOP uses OAuth instead of a fixed token. Add it without a header and log in when Claude Code asks:

```bash
claude mcp add --transport http --scope user whoop https://whoop.example.com/mcp
```

## Check

- `claude mcp list` shows "Connected" for each server. On "Failed to connect", `claude mcp get <name>` shows the reason.
- In Claude Code, `/mcp` shows the status and starts OAuth logins.
- Without the token, Caddy must answer 401: `curl -i https://mcp-cal.int.example.com/mcp`
- From outside your LAN / Tailscale it must answer 403.

## Where the token ends up

The token sits in plain text in `~/.claude.json` and in your shell history.
Treat the file like a password and remove the line from your history (for Bash in `~/.bash_history`).
If a token leaks, create a new one, change it where it is checked (the Caddyfile, or `MCP_API_KEY` for Proxmox), reload, and add the server again.

## The claude.ai app (custom connector)

The claude.ai app connects from Anthropic's servers, so it can not reach `*.int.example.com`.
For that you need the public OAuth entrance described in [calendar/README.md](../calendar/README.md).
Menu path (October 2026): Customize > Connectors > + Add > Add custom connector.
