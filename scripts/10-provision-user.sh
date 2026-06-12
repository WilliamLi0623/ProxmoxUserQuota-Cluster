#!/usr/bin/env bash
# Provision (or reconcile) one user's quota pool and ACLs. Idempotent.
#
# Usage: 10-provision-user.sh <user@realm> [-s storage]... [-b bridge]...
#   -s  storage the user may allocate disks on (repeatable)
#   -b  bridge/VNet the user may attach NICs to (repeatable)
#
# Run as root on any cluster node. Roles must exist first (00-create-roles.sh).
# Safe to re-run any time, e.g. as a reconciler after an LDAP realm sync.
set -euo pipefail

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
}

userid="${1:-}"
[[ -n "$userid" && "$userid" == *@* ]] || usage
shift

storages=()
bridges=()
while getopts ":s:b:" opt; do
  case "$opt" in
    s) storages+=("$OPTARG") ;;
    b) bridges+=("$OPTARG") ;;
    *) usage ;;
  esac
done

uname="${userid%@*}"
# Pool ids allow [A-Za-z0-9._-]. No silent sanitization: the username->pool
# mapping must stay injective (two users must never collapse onto one pool).
if [[ ! "$uname" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: username '$uname' contains characters not allowed in a pool id." >&2
  echo "Add an explicit manual mapping instead of sanitizing." >&2
  exit 2
fi
pool="uq-${uname}"

if ! pveum pool add "$pool" --comment "ProxmoxUserQuota pool for ${userid}" 2>/dev/null; then
  echo "pool ${pool} already exists"
fi

pveum acl modify "/pool/${pool}" --users "$userid" --roles UQ-VMUser
echo "ok: ${userid} -> UQ-VMUser on /pool/${pool}"

for s in ${storages[@]+"${storages[@]}"}; do
  pveum acl modify "/storage/${s}" --users "$userid" --roles UQ-Storage
  echo "ok: ${userid} -> UQ-Storage on /storage/${s}"
done

for b in ${bridges[@]+"${bridges[@]}"}; do
  pveum acl modify "/sdn/zones/localnetwork/${b}" --users "$userid" --roles UQ-Net
  echo "ok: ${userid} -> UQ-Net on /sdn/zones/localnetwork/${b}"
done

echo "provisioned: ${userid} (pool ${pool})"
