#!/usr/bin/env bash
# Provision a per-user ZFS-backed storage with a HARD quota: defense in depth
# behind the proxy (P6). Even if the proxy is bypassed, ZFS refuses allocation
# beyond the dataset quota. Idempotent. Run as root on the node owning the zpool.
#
# Usage: 40-provision-storage.sh <user@realm> -q <GiB> [-z zpool] [-n node]
#   -q  hard quota in GiB for this user's storage (required)
#   -z  parent ZFS pool/dataset to nest under (default: pool)
#   -n  restrict the PVE storage to this node (default: $(hostname))
#
# Creates: dataset <zpool>/uq-<user> (quota=<GiB>G), PVE zfspool storage
# uq-<user> (content rootdir,images), and UQ-Storage ACL for the user on it.
# Grant the user UQ-Storage ONLY here, never on the shared zpool storage,
# or the hard quota is bypassable. Then set in quotas.yaml:
#     disk-gib: { uq-<user>: <GiB> }   # storage id matches the PVE storage
set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }

userid="${1:-}"
[[ -n "$userid" && "$userid" == *@* ]] || usage
shift

quota_gib=""
zpool="pool"
node="$(hostname)"
while getopts ":q:z:n:" opt; do
  case "$opt" in
    q) quota_gib="$OPTARG" ;;
    z) zpool="$OPTARG" ;;
    n) node="$OPTARG" ;;
    *) usage ;;
  esac
done
[[ "$quota_gib" =~ ^[0-9]+$ && "$quota_gib" -gt 0 ]] || { echo "ERROR: -q <GiB> required (positive integer)" >&2; exit 1; }

uname="${userid%@*}"
if [[ ! "$uname" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: username '$uname' has characters not allowed in a storage/pool id." >&2
  exit 2
fi
storeid="uq-${uname}"
dataset="${zpool}/uq-${uname}"

# 1. dataset + hard quota (quota bounds children AND snapshots, the conservative
#    backstop; a thick zvol's refreservation also counts, so an over-size disk
#    create fails at the ZFS layer regardless of the proxy).
if ! zfs list -H -o name "$dataset" >/dev/null 2>&1; then
  zfs create "$dataset"
  echo "ok: created dataset $dataset"
else
  echo "dataset $dataset already exists"
fi
zfs set "quota=${quota_gib}G" "$dataset"
echo "ok: zfs quota=${quota_gib}G on $dataset"

# 2. PVE zfspool storage pointing at the dataset, pinned to the node.
if pvesh get "/storage/${storeid}" >/dev/null 2>&1; then
  echo "storage ${storeid} already exists"
else
  pvesm add zfspool "$storeid" --pool "$dataset" \
    --content rootdir,images --nodes "$node"
  echo "ok: added zfspool storage ${storeid} -> ${dataset} (node ${node})"
fi

# 3. user may allocate ONLY on their own storage.
pveum acl modify "/storage/${storeid}" --users "$userid" --roles UQ-Storage
echo "ok: ${userid} -> UQ-Storage on /storage/${storeid}"

echo "provisioned storage: ${userid} -> ${storeid} (${quota_gib} GiB hard cap)"
echo "NOTE: set the matching soft cap in quotas.yaml so the GUI shows a clean"
echo "      reason before ZFS ever refuses:  disk-gib: { ${storeid}: ${quota_gib} }"
