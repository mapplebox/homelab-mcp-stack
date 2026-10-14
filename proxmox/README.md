# Proxmox MCP (ProxmoxMCP-Plus)

Lets Claude list nodes, VMs and containers, check storage, read guest configs, take snapshots and (if you allow it) start and stop guests.
Internal only. This one never gets a public entrance.

Guide: [mapplebox.com/proxmox-claude-mcp](https://mapplebox.com/proxmox-claude-mcp/) (EN), [mapplebox.de/proxmox-claude-mcp](https://mapplebox.de/proxmox-claude-mcp/) (DE).

| | |
|---|---|
| Upstream | [RekklesNA/ProxmoxMCP-Plus](https://github.com/RekklesNA/ProxmoxMCP-Plus), PyPI [`proxmox-mcp-plus`](https://pypi.org/project/proxmox-mcp-plus/) |
| Version we run | 0.5.27 (newer releases exist; pin the version you tested) |
| Transport | Streamable HTTP, port 8000, path `/mcp` |
| Auth | `MCP_API_KEY`, checked by the server itself. Clients send `Authorization: Bearer <MCP_API_KEY>`. Caddy only limits access to LAN and Tailscale. |

## Files

| File | Goes to |
|---|---|
| [proxmox-mcp.service](proxmox-mcp.service) | `/etc/systemd/system/proxmox-mcp.service` |
| [proxmox-mcp.env.example](proxmox-mcp.env.example) | `/etc/proxmox-mcp/proxmox-mcp.env` (640 root:mcp) |
| [config.example.json](config.example.json) | `/etc/proxmox-mcp/config.json` (640 root:mcp) |
| [nftables.conf](nftables.conf) | `/etc/nftables.conf` (port 8000 only from Caddy) |
| [make-ca.sh](make-ca.sh) | run on your admin machine |
| [pve-user.md](pve-user.md) | Proxmox user, token, ACL |
| [install-cert.md](install-cert.md) | Proxmox node certificate |

## The TLS problem this solves

Python 3.13 turned on `VERIFY_X509_STRICT` by default. Older Proxmox installs created their cluster CA without the `keyUsage` extension, so a strict check rejects it, and ProxmoxMCP-Plus can not talk to the API with `verify_ssl: true`:

```
certificate verify failed: CA cert does not include key usage extension
```

Check your CA first, on a Proxmox node:

```bash
openssl x509 -in /etc/pve/pve-root-ca.pem -noout -ext keyUsage
```

If this prints `Certificate Sign, CRL Sign`, your CA is fine: copy `/etc/pve/pve-root-ca.pem` to the LXC as `/etc/proxmox-mcp/homelab-ca.pem` (same `pct push` route as in step 5 below) and skip make-ca.sh. At the time of writing, pve-cluster 9.1.2 creates new CAs with keyUsage (bug #6701, [patch](https://lists.proxmox.com/pipermail/pve-devel/2026-January/078189.html)). An existing CA is not changed by the update. If the command prints nothing, your CA lacks the extension and you need the steps below.

Setting `verify_ssl: false` would make the error go away and also turn off the check that you are talking to your real Proxmox host. We went the other way: a small own CA whose certs pass strict checks.

[make-ca.sh](make-ca.sh) creates:

- **CA**: CN "Homelab Proxmox CA", ECDSA P-256, 10 years. `basicConstraints` critical `CA:TRUE, pathlen:0`, `keyUsage` critical `keyCertSign, cRLSign`.
- **Host cert** (one per node): ECDSA P-256. `basicConstraints` critical `CA:FALSE`, `keyUsage` critical `digitalSignature, keyEncipherment`, `extendedKeyUsage serverAuth`, `subjectAltName IP:<host-ip>, DNS:<hostname>, DNS:localhost, IP:127.0.0.1`.
- Both also carry Subject/Authority Key Identifiers. Strict mode wants the Authority Key Identifier on the host cert.

The script never overwrites an existing key or cert, it stops instead. It checks the result with `openssl verify -x509_strict`. We also tested the output with a Python 3.13 TLS handshake in strict mode.

## Setup

1. **LXC**: unprivileged Debian, 1 core, 512 MB RAM, 4 GB disk, fixed IP (example `192.168.1.25`). One MCP server per standalone host, or one for a whole cluster. Get a Debian 13 template on the Proxmox host:

   ```bash
   pveam update
   pveam available --section system | grep debian-13
   pveam download local <name-from-the-list>
   ```

2. **Proxmox user and token**: follow [pve-user.md](pve-user.md).
3. **Certificates**: follow [install-cert.md](install-cert.md) for each node.
4. **Install the server** in the LXC:

   ```bash
   apt update && apt install -y python3 curl ca-certificates nftables
   useradd --system --home /var/lib/proxmox-mcp --shell /usr/sbin/nologin mcp
   install -d -o mcp -g mcp -m 750 /var/lib/proxmox-mcp
   install -d -o root -g mcp -m 750 /etc/proxmox-mcp
   curl -LsSf https://astral.sh/uv/install.sh | sh
   source ~/.local/bin/env
   uv venv --python /usr/bin/python3 /opt/proxmox-mcp
   uv pip install --python /opt/proxmox-mcp/bin/python "proxmox-mcp-plus==0.5.27"
   ```

5. **Config**: create both files empty with the right owner and mode first, then paste the content of [config.example.json](config.example.json) and [proxmox-mcp.env.example](proxmox-mcp.env.example) and fill in the token secret and `MCP_API_KEY` (`openssl rand -hex 32`):

   ```bash
   install -m 640 -o root -g mcp /dev/null /etc/proxmox-mcp/config.json
   nano /etc/proxmox-mcp/config.json
   install -m 640 -o root -g mcp /dev/null /etc/proxmox-mcp/proxmox-mcp.env
   nano /etc/proxmox-mcp/proxmox-mcp.env
   ```

   Get the CA into the LXC. From your admin machine via the Proxmox host (`<ct-id>` is the LXC's ID):

   ```bash
   scp ./pki/homelab-ca.pem root@192.168.1.5:/root/homelab-ca.pem
   ssh root@192.168.1.5 pct push <ct-id> /root/homelab-ca.pem /etc/proxmox-mcp/homelab-ca.pem --perms 644
   ```
6. **Firewall**: this LXC has no Docker, and Debian uses nftables. Copy [nftables.conf](nftables.conf) to `/etc/nftables.conf`, set `CADDY_IP`, then:

   ```bash
   nft -c -f /etc/nftables.conf
   systemctl enable --now nftables
   nft list ruleset
   ```

   `nft -c` only checks the syntax and changes nothing. The file starts with `flush ruleset`, which replaces all rules in this LXC (an LXC has its own network namespace, the Proxmox host is not affected). The input policy stays `accept` and only port 8000 is restricted, so SSH keeps working.
7. **Start**:

   ```bash
   systemctl daemon-reload
   systemctl enable --now proxmox-mcp
   journalctl -u proxmox-mcp -f
   ```

8. **Caddy**: the `mcp-proxmox.int.example.com` block in [../common/Caddyfile.snippets](../common/Caddyfile.snippets). It only does `int_only` and the reverse proxy; the token check happens in ProxmoxMCP-Plus.
9. **Claude Code**:

   ```bash
    claude mcp add --transport http --scope user proxmox \
     https://mcp-proxmox.int.example.com/mcp \
     --header "Authorization: Bearer <your-long-random-value>"
   ```

   The leading space keeps the command out of your Bash history (with the usual `HISTCONTROL=ignoreboth`). The key still ends up in plain text in `~/.claude.json`, so treat that file like a password.

## Safety rules we use

- A dedicated user and token. Revoking the token cuts Claude off at once.
- `command_policy.mode: deny_all`: no shell commands inside guests.
- Claude takes a snapshot before changes and asks before anything disruptive (stop, rollback, delete). A human confirms.
- Internal only: LAN and Tailscale via Caddy, `MCP_API_KEY` checked by the server, nftables on the LXC.
- If you only want Claude to look, use the PVEAuditor role instead of PVEAdmin.
