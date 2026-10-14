# Installing the host certificate on a Proxmox node

Checked against the Proxmox wiki page [Certificate Management](https://pve.proxmox.com/wiki/Certificate_Management)
and the [pvenode(1) man page](https://pve.proxmox.com/pve-docs/pvenode.1.html).

Proxmox uses a custom certificate for the web UI and API (port 8006) when these two files exist:

```
/etc/pve/nodes/<node>/pveproxy-ssl.pem   # certificate (chain)
/etc/pve/nodes/<node>/pveproxy-ssl.key   # private key, without a passphrase
```

`/etc/pve/local` is a symlink to `/etc/pve/nodes/<this-node>`, so on the node itself you can also use `/etc/pve/local/...`.
The files in `/etc/pve/pve-root-ca.pem` and `pve-ssl.pem` stay untouched; Proxmox keeps using them internally.

## 1. Create the cert

On your admin machine (where the CA key lives):

```bash
./make-ca.sh pve1.example.com 192.168.1.5 ./pki
# creates ./pki/homelab-ca.pem, ./pki/homelab-ca.key,
#         ./pki/pve1.example.com.pem, ./pki/pve1.example.com.key
```

Do this once per node. The CA is created on the first run and reused after that.

### Without the script

The same by hand. CA (once):

```bash
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout homelab-ca.key -out homelab-ca.pem -days 3650 \
  -subj "/CN=Homelab Proxmox CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
```

Host cert: write the extensions to `pve1.example.com.ext`:

```
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = IP:192.168.1.5,DNS:pve1.example.com,DNS:localhost,IP:127.0.0.1
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
```

Then create key, request and cert, and check it:

```bash
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout pve1.example.com.key -out pve1.example.com.csr -subj "/CN=pve1.example.com"
openssl x509 -req -in pve1.example.com.csr -CA homelab-ca.pem -CAkey homelab-ca.key \
  -CAcreateserial -out pve1.example.com.pem -days 825 -sha256 -extfile pve1.example.com.ext
openssl verify -x509_strict -CAfile homelab-ca.pem pve1.example.com.pem
```

Unlike the script, these commands overwrite existing files without asking.

## 2. Copy it to the node

```bash
scp ./pki/pve1.example.com.pem root@192.168.1.5:/etc/pve/nodes/pve1/pveproxy-ssl.pem
scp ./pki/pve1.example.com.key root@192.168.1.5:/etc/pve/nodes/pve1/pveproxy-ssl.key
```

Replace `pve1` with the node name (`hostname` on the node).
`/etc/pve` is the cluster file system; it handles the permissions itself.

## 3. Restart pveproxy

```bash
ssh root@192.168.1.5 systemctl restart pveproxy
```

Alternative to steps 2 and 3, on the node itself:

```bash
pvenode cert set /root/pve1.example.com.pem /root/pve1.example.com.key --force 1 --restart 1
```

## 4. Check

```bash
openssl s_client -connect 192.168.1.5:8006 -CAfile ./pki/homelab-ca.pem -verify_return_error </dev/null 2>/dev/null | grep "Verify return code"
# Verify return code: 0 (ok)
```

## 5. Trust the CA on the MCP server

Copy `homelab-ca.pem` from your admin machine into the MCP LXC via the Proxmox host (`<ct-id>` is the LXC's ID):

```bash
scp ./pki/homelab-ca.pem root@192.168.1.5:/root/homelab-ca.pem
ssh root@192.168.1.5 pct push <ct-id> /root/homelab-ca.pem /etc/proxmox-mcp/homelab-ca.pem --perms 644
```

Then, inside the LXC:

```bash
# proxmox-mcp.env: REQUESTS_CA_BUNDLE=/etc/proxmox-mcp/homelab-ca.pem
systemctl restart proxmox-mcp
```

Bonus: import `homelab-ca.pem` into your browser or OS trust store and the certificate warning on port 8006 goes away.

## Undo

```bash
pvenode cert delete 1   # removes pveproxy-ssl.pem/.key and restarts pveproxy
```

Proxmox falls back to its own self-signed certificate.
