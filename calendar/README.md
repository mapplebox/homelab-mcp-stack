# iCloud calendar MCP

Gives Claude access to your iCloud calendars over CalDAV: list-calendars, list-events, create-event, update-event, delete-event (plus CalDAV to-dos, see the note at the end).
Works in Claude Code (internal entrance) and, optionally, in the claude.ai app as a custom connector (public entrance).

Guide: [mapplebox.com/icloud-calendar-claude-mcp](https://mapplebox.com/icloud-calendar-claude-mcp/) (EN), [mapplebox.de/icloud-kalender-claude-mcp](https://mapplebox.de/icloud-kalender-claude-mcp/) (DE).
Background on Caddy and securing MCP connectors: [mapplebox.com/claude-homelab-mcp-secure](https://mapplebox.com/claude-homelab-mcp-secure/) (EN), [mapplebox.de/claude-homelab-mcp-connectors-sicher](https://mapplebox.de/claude-homelab-mcp-connectors-sicher/) (DE).

| Part | Upstream | Version we run |
|---|---|---|
| CalDAV MCP server | [dominik1001/caldav-mcp](https://github.com/dominik1001/caldav-mcp) (npm `caldav-mcp`) | 0.10.0 |
| stdio to HTTP bridge | [supercorp-ai/supergateway](https://github.com/supercorp-ai/supergateway) (npm `supergateway`) | 4.1.0 |
| OAuth front door | [sigbit/mcp-auth-proxy](https://github.com/sigbit/mcp-auth-proxy) (`ghcr.io/sigbit/mcp-auth-proxy`) | v2.10.2 |

Placeholders: `192.168.1.10` Caddy, `192.168.1.21` calendar LXC, `mcp-cal.int.example.com` internal, `cal.example.com` public.

## 1. Apple app-specific password

iCloud CalDAV does not take your normal Apple password. Two-factor authentication must be on.

1. Sign in at [account.apple.com](https://account.apple.com).
2. Sign-In and Security > App-Specific Passwords > Generate an app-specific password, name it e.g. "Claude Calendar".
3. Copy it into your password manager.

Changing your main Apple password revokes all app-specific passwords.

## 2. LXC with Docker

Unprivileged Debian LXC with a fixed IP (or DHCP reservation). On the Proxmox host:

```bash
pct set <vmid> --features nesting=1,keyctl=1
pct reboot <vmid>
```

Inside the LXC:

```bash
apt update && apt install -y curl
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
mkdir -p /opt/mcp-calendar && cd /opt/mcp-calendar
```

## 3. Dockerfile

[Dockerfile](Dockerfile): caldav-mcp only speaks stdio, supergateway serves it over Streamable HTTP at `/mcp` on port 3000 (health check `/healthz` answers "ok"). Versions are pinned; to update, change them and run `docker compose up -d --build`.

## 4. docker-compose.yml and the .env files

[docker-compose.yml](docker-compose.yml) runs `caldav-mcp` and `auth-proxy` (mcp-auth-proxy, OAuth 2.1 for the claude.ai app). Change `TZ: Europe/Berlin` to your time zone.

The ports are published as `0.0.0.0:3000:3000` on purpose. Without `0.0.0.0:` Docker also publishes them over IPv6, where the IPv4 firewall rule from step 5 does not apply.

```bash
cp .env.example .env            # Apple ID e-mail + app-specific password
openssl rand -base64 24         # login password for the auth proxy
cp auth.env.example auth.env    # PASSWORD=<output-from-openssl>
chmod 600 .env auth.env
mkdir -p auth-data
```

If you pick your own password for `auth.env`, leave out `$`: Docker Compose reads it as a variable.
Do not start the containers yet, the firewall comes first. Add `auth-data/` to your backups.

### If Claude Code is all you need

Delete the whole `auth-proxy` block from `docker-compose.yml`, do not create `auth.env` or `auth-data`, put only `3000` after `--dports` in step 5, and skip step 8. Everything stays inside your LAN.

## 5. Firewall: only Caddy gets in

Check the interface name with `ip -br link` (LXC: usually `eth0`, VM: often `ens18`). Copy [../common/mcp-firewall.service](../common/mcp-firewall.service) to `/etc/systemd/system/mcp-firewall.service`, adjust Caddy IP, ports and interface ([details](../common/README.md)). Then enable it and only after that start the containers:

```bash
systemctl daemon-reload
systemctl enable --now mcp-firewall.service
iptables -L DOCKER-USER -n -v --line-numbers
cd /opt/mcp-calendar
docker compose up -d --build
```

The DROP rule must show up exactly once.

## 6. Internal entrance in Caddy (Bearer token)

Generate a token with `openssl rand -hex 32` and keep it in your password manager. The container does not need it, only Caddy and Claude Code.
Use the `(int_only)` snippet and the `mcp-cal.int.example.com` block from [../common/Caddyfile.snippets](../common/Caddyfile.snippets). The file header there shows how to add the DNS module (`caddy add-package`), pass `IONOS_API_TOKEN` via `systemctl edit caddy`, and set the Caddyfile to `640 root:caddy`.

`mcp-cal.int.example.com` must resolve to Caddy's IP inside your LAN (router DNS, Pi-hole, ...).

## 7. Claude Code

```bash
claude mcp add --transport http --scope user calendar \
  https://mcp-cal.int.example.com/mcp \
  --header "Authorization: Bearer <token-from-openssl>"
```

`claude mcp list` should show "Connected". The token is now in plain text in `~/.claude.json` and your shell history; remove it from the history.

## 8. Optional: public entrance for the claude.ai app

Needs a real public IPv4 (no DS-Lite / CGNAT), a public DNS record for `cal.example.com`, and ports 80 and 443 forwarded to Caddy. Use the `cal.example.com` block from [../common/Caddyfile.snippets](../common/Caddyfile.snippets): `/mcp` only answers Anthropic's outbound range `160.79.104.0/21` ([check it is current](https://platform.claude.com/docs/en/api/ip-addresses)); the OAuth login pages stay reachable and are protected by the password in `auth.env`.

After `systemctl reload caddy`, in Claude (Free, Pro, Max; on Team/Enterprise an Owner adds it in the organization settings):

1. Customize > Connectors > + Add > Add custom connector.
2. Name e.g. "Apple Calendar", URL `https://cal.example.com/mcp`, Continue.
3. Continue again, Authentication "Sign in now", leave OAuth client on the default, no request headers.
4. Add. The mcp-auth-proxy login page opens; enter the password from `auth.env`.

Turn the connector on in a chat via "+" > Connectors. Menu names change; if in doubt, [Anthropic's help page](https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp) wins.

## Check

- In the LXC: `docker compose ps` shows both containers running, `curl http://localhost:3000/healthz` answers "ok".
- Without token: `curl -i https://mcp-cal.int.example.com/mcp` returns 401. With token it must not return 401.
- From another LAN machine: `curl -m 5 http://192.168.1.21:3000/healthz` times out (firewall works).
- Public entrance only: `https://cal.example.com/.well-known/oauth-authorization-server` returns 200, and `curl -i https://cal.example.com/mcp` from home returns 403.
- From outside (phone hotspot): `curl -i --resolve mcp-cal.int.example.com:443:<your-public-ip> https://mcp-cal.int.example.com/mcp` returns 403.

## Notes

- **Why caldav-mcp:** dav-mcp always signs in over CardDAV on the same URL, and iCloud keeps contacts on another server, so it failed every time. caldav-mcp only does CalDAV.
- **To-dos:** caldav-mcp can create CalDAV tasks. Apple moved Reminders to a new format with iOS 13, though, so these tasks do not show up in the Reminders app, and existing reminders are not reachable over CalDAV.
- **Caddy 502:** wrong Caddy IP in the firewall unit, or the interface after `-i` does not match `ip -br link`.
- **Security:** an app-specific password can reach iCloud mail, contacts and calendars. Hence the separate LXC, `chmod 600` and the firewall. Revoke it any time at account.apple.com. Claude can also delete events, so read what it wants to do before you approve.
