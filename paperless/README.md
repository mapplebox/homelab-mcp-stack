# Paperless-ngx MCP

Lets Claude search, read, tag and file documents in Paperless-ngx. Internal only.

| | |
|---|---|
| Upstream | [cubinet-code/paperless-ngx-mcp](https://github.com/cubinet-code/paperless-ngx-mcp) |
| Image | `ghcr.io/cubinet-code/paperless-ngx-mcp:3.2.1` |
| Port | 3000 (`--http --port 3000`), Streamable HTTP at `/mcp` |
| Auth | Bearer token checked by Caddy |

## Setup

1. In Paperless, open the profile of the user Claude should act as and create an API token. Claude can see and change everything that user can. A separate user with limited permissions is the careful option.
2. LXC with Docker, fixed IP (example `192.168.1.23`).
3. In `/opt/mcp-paperless`:

   ```bash
   cp .env.example .env && chmod 600 .env && nano .env
   docker compose up -d
   ```

4. Set `PAPERLESS_URL` to the internal address of Paperless (example `http://192.168.1.30:8000`) and `PAPERLESS_PUBLIC_URL` to the URL you open in the browser, so links in Claude's answers work.
5. Firewall: [../common/mcp-firewall.service](../common/mcp-firewall.service) with `MCP_PORTS=3000`.
6. Caddy block `mcp-paperless.int.example.com` from [../common/Caddyfile.snippets](../common/Caddyfile.snippets).
7. `claude mcp add`, see [../common/claude-mcp-add.md](../common/claude-mcp-add.md).

The server has delete tools (documents, tags, correspondents). Paperless keeps deleted documents in its trash for a while, but tags and correspondents are gone for good. Read what Claude wants to do before you confirm.
