#!/usr/bin/env bash
# Create/refresh the ProxmoxUserQuota custom roles. Idempotent.
# Run as root on any node of the target PVE cluster.
#
# Rationale for every privilege: Docs repo, pool-rbac.md.
set -euo pipefail

role_set() {
  local role="$1" privs="$2"
  if ! pveum role add "$role" -privs "$privs" 2>/dev/null; then
    pveum role modify "$role" -privs "$privs"
  fi
  echo "ok: role $role"
}

# Self-service VM owner. Granted ONLY on /pool/uq-<user>.
# Excluded on purpose: Pool.Allocate (pool-membership lock), VM.Migrate,
# VM.Monitor, Datastore.*, Permissions.*, Sys.*, Mapping.*.
role_set UQ-VMUser "Pool.Audit VM.Allocate VM.Audit VM.Backup VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Console VM.PowerMgmt VM.Snapshot VM.Snapshot.Rollback"

# Granted on /storage/<id> for each storage the user may allocate disks on.
role_set UQ-Storage "Datastore.AllocateSpace Datastore.Audit"

# Granted on /sdn/zones/localnetwork/<bridge> (or specific VNets).
role_set UQ-Net "SDN.Use"

# Service-account role for the proxy's read-only accounting (P3+). It looks
# wider than "audit" because PVE 9.x gates several accounting *reads* behind
# write-ish privileges (validated on 9.2.3):
#   VM.Config.Disk          - size unused[n] disks via the storage content API
#   Datastore.AllocateSpace - } read a backup's embedded config via
#   VM.Backup               - } vzdump/extractconfig (restore admission)
# The token only ever issues GETs, so it stays effectively read-only.
role_set UQ-ProxyAudit "VM.Audit VM.Config.Disk VM.Backup Pool.Audit Datastore.Audit Datastore.AllocateSpace Sys.Audit SDN.Audit"

echo "all roles ensured"
