# Proxmox user, API token and permissions for the MCP server

Run these on a Proxmox node as root (in a cluster, once is enough: `/etc/pve` is shared).
Syntax checked against the [pveum(1) man page](https://pve.proxmox.com/pve-docs/pveum.1.html) and the [User Management wiki](https://pve.proxmox.com/wiki/User_Management).

## 1. Dedicated user

```bash
pveum user add mcp@pve --comment "MCP server for Claude"
```

The user lives in the `pve` realm and gets no password. It only exists to own the token, nobody logs in with it.

## 2. API token

```bash
pveum user token add mcp@pve mcp --comment "ProxmoxMCP-Plus" --privsep 1
```

- The full token ID is `mcp@pve!mcp`. In `config.json` you enter `"user": "mcp@pve"` and `"token_name": "mcp"`.
- The output shows the secret (`value`) exactly once. Copy it straight into `config.json` (`token_value`) on the MCP LXC. Do not paste it into a chat, a ticket or git.
- `--privsep 1` is the default. With privilege separation the token has no rights of its own. Its effective rights are the intersection of what the user has and what the token has, so both need an ACL (next step).

## 3. Permissions (pick one)

**Read and act** (what we run: Claude can start/stop guests, take snapshots, and so on):

```bash
pveum acl modify / --roles PVEAdmin --users mcp@pve
pveum acl modify / --roles PVEAdmin --tokens 'mcp@pve!mcp'
```

**Read only** (Claude can look at everything and change nothing):

```bash
pveum acl modify / --roles PVEAuditor --users mcp@pve
pveum acl modify / --roles PVEAuditor --tokens 'mcp@pve!mcp'
```

PVEAdmin "can do most tasks, but has no rights to modify system settings" and can not change permissions. PVEAuditor is read only.
The single quotes matter: in bash an unquoted `!` can trigger history expansion.

You can also scope the ACL to a path smaller than `/`, for example `/vms/100` or `/pool/<name>`.

## 4. Check

```bash
pveum user token permissions mcp@pve mcp
```

## Revoke

```bash
pveum user token delete mcp@pve mcp
```

The MCP server stops working immediately. Create a new token and update `config.json` to bring it back.
