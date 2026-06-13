#!/usr/bin/env bash
# Provision the proxy service account: uq-proxy@pve + an API token + the
# read-only ACL the accounting engine needs. Idempotent. Run as root on a
# cluster node. Roles must exist first (00-create-roles.sh).
#
# Usage: 30-provision-proxy.sh [-t tokenid] [-f token-file] [--rotate]
#   -t  token id (default: audit)
#   -f  file to write the token secret for the proxy
#       (default: /etc/uq-proxy/pve-token), as  uq-proxy@pve!<tokenid>=<secret>
#   --rotate  delete and recreate the token (writes a fresh secret)
#
# PVE shows the token secret only once, at creation, so the file is written
# only when the token is (re)created. On a SEPARATE proxy host, copy the file
# there and restart uq-proxy. The proxy reads it under systemd DynamicUser=yes
# + SupplementaryGroups=www-data, hence the root:www-data 0640 mode.
set -euo pipefail

USERID="uq-proxy@pve"
TOKENID="audit"
TOKENFILE="/etc/uq-proxy/pve-token"
ROTATE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t) TOKENID="${2:?-t needs a value}"; shift 2 ;;
    -f) TOKENFILE="${2:?-f needs a value}"; shift 2 ;;
    --rotate) ROTATE=1; shift ;;
    *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1 ;;
  esac
done

# Local PVE realm, never LDAP/OIDC: the proxy must survive an IdP outage.
if ! pveum user add "$USERID" --comment "ProxmoxUserQuota proxy service account" 2>/dev/null; then
  echo "user $USERID already exists"
fi

# Read-only accounting role on / (propagates to all guests/storages/pools).
pveum acl modify / --users "$USERID" --roles UQ-ProxyAudit
echo "ok: $USERID -> UQ-ProxyAudit on /"

full="${USERID}!${TOKENID}"
exists="$(pveum user token list "$USERID" --output-format json 2>/dev/null \
  | python3 -c 'import sys,json
ts=json.load(sys.stdin)
print("1" if any(t.get("tokenid")==sys.argv[1] for t in ts) else "0")' "$TOKENID" 2>/dev/null || echo 0)"

if [[ "$exists" == "1" && "$ROTATE" == "0" ]]; then
  echo "token $full already exists; secret not re-readable (use --rotate to regenerate)"
  exit 0
fi
if [[ "$exists" == "1" ]]; then
  pveum user token remove "$USERID" "$TOKENID" >/dev/null
fi

# privsep 0: the token inherits the user's UQ-ProxyAudit privileges.
secret="$(pveum user token add "$USERID" "$TOKENID" --privsep 0 --output-format json \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')"

mkdir -p "$(dirname "$TOKENFILE")"
printf '%s=%s' "$full" "$secret" > "$TOKENFILE"
if getent group www-data >/dev/null 2>&1; then
  chgrp www-data "$TOKENFILE" && chmod 640 "$TOKENFILE"
else
  chmod 600 "$TOKENFILE"
fi
echo "ok: wrote token for $full to $TOKENFILE"
echo "NOTE: if the proxy runs on another host, copy $TOKENFILE there, then restart uq-proxy."
