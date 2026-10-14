#!/usr/bin/env bash
# make-ca.sh: small private CA plus one TLS cert per Proxmox host.
#
# Why: Python 3.13 turns on VERIFY_X509_STRICT by default. The CA that Proxmox
# generates itself has no keyUsage extension, so strict verification rejects it
# and ProxmoxMCP-Plus fails with verify_ssl=true. This script builds a CA and
# host certs that pass strict verification.
#
# Usage:
#   ./make-ca.sh <hostname> <host-ip> [output-dir]
#   ./make-ca.sh pve1.example.com 192.168.1.5
#
# First run creates the CA (homelab-ca.key / homelab-ca.pem) in the output dir.
# Later runs reuse that CA and only add a cert for the new host.
# Existing keys and certs are never overwritten: the script stops instead.
#
# Output per host:  <hostname>.key  <hostname>.pem  (install as pveproxy-ssl.key / pveproxy-ssl.pem)
# Keep homelab-ca.key offline. Only homelab-ca.pem goes to the MCP server and browsers.

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 <hostname> <host-ip> [output-dir]" >&2
  exit 1
fi

HOST="$1"
IP="$2"
OUT="${3:-.}"
CA_DAYS=3650      # 10 years
HOST_DAYS=825     # about 2 years 3 months

case "$HOST" in
  *[!A-Za-z0-9.-]*|"") echo "error: hostname may only contain letters, digits, dots and dashes" >&2; exit 1 ;;
esac
case "$IP" in
  *[!0-9.]*|"") echo "error: host-ip must be an IPv4 address" >&2; exit 1 ;;
esac

mkdir -p "$OUT"
cd "$OUT"
umask 077

CA_KEY=homelab-ca.key
CA_CRT=homelab-ca.pem
HOST_KEY="$HOST.key"
HOST_CSR="$HOST.csr"
HOST_CRT="$HOST.pem"

for f in "$HOST_KEY" "$HOST_CRT"; do
  if [ -e "$f" ]; then
    echo "error: $OUT/$f already exists. Refusing to overwrite. Move it away first." >&2
    exit 1
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------- CA (only if it does not exist yet) ----------
if [ -e "$CA_KEY" ] || [ -e "$CA_CRT" ]; then
  if [ ! -e "$CA_KEY" ] || [ ! -e "$CA_CRT" ]; then
    echo "error: found only one of $CA_KEY / $CA_CRT. Fix that by hand, nothing was changed." >&2
    exit 1
  fi
  echo "Reusing existing CA: $OUT/$CA_CRT"
else
  cat > "$TMP/ca.cnf" <<'EOF'
[req]
distinguished_name = dn
prompt             = no
x509_extensions    = v3_ca

[dn]
CN = Homelab Proxmox CA

[v3_ca]
basicConstraints     = critical, CA:TRUE, pathlen:0
keyUsage             = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF
  # Build in the temp dir first, move into place only when everything worked.
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$TMP/ca.key"
  openssl req -x509 -new -config "$TMP/ca.cnf" -key "$TMP/ca.key" -sha256 -days "$CA_DAYS" -out "$TMP/ca.pem"
  chmod 600 "$TMP/ca.key"
  chmod 644 "$TMP/ca.pem"
  mv -n "$TMP/ca.key" "$CA_KEY"
  mv -n "$TMP/ca.pem" "$CA_CRT"
  echo "Created CA: $OUT/$CA_CRT (key: $OUT/$CA_KEY, keep it offline)"
fi

# ---------- host cert ----------
cat > "$TMP/host.ext" <<EOF
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectAltName         = IP:$IP, DNS:$HOST, DNS:localhost, IP:127.0.0.1
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid
EOF

# Build in the temp dir first, move into place only when everything worked.
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$TMP/host.key"
openssl req -new -key "$TMP/host.key" -subj "/CN=$HOST" -out "$TMP/$HOST_CSR"
openssl x509 -req -in "$TMP/$HOST_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" \
  -set_serial "0x$(openssl rand -hex 16)" \
  -sha256 -days "$HOST_DAYS" -extfile "$TMP/host.ext" -out "$TMP/host.pem"

# Self check with strict X.509 rules (same idea as Python 3.13).
openssl verify -x509_strict -CAfile "$CA_CRT" "$TMP/host.pem"

chmod 600 "$TMP/host.key"
chmod 644 "$TMP/host.pem"
mv -n "$TMP/host.key" "$HOST_KEY"
mv -n "$TMP/host.pem" "$HOST_CRT"

echo
echo "Done:"
echo "  $OUT/$HOST_CRT  -> /etc/pve/nodes/<node>/pveproxy-ssl.pem"
echo "  $OUT/$HOST_KEY  -> /etc/pve/nodes/<node>/pveproxy-ssl.key"
echo "  $OUT/$CA_CRT    -> /etc/proxmox-mcp/homelab-ca.pem on the MCP server"
