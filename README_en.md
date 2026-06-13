# ProxmoxUserQuota-Cluster

[中文](README.md) | **English**

PVE cluster-side scripts: create the minimal custom roles, provision per-user quota pools/ACLs, and verify the P0 exit criteria. These scripts only *prepare and constrain* the cluster — quota enforcement itself is done by [ProxmoxUserQuota-Proxy](https://github.com/WilliamLi0623/ProxmoxUserQuota-Proxy) (from P4). All scripts are idempotent and safe to re-run (they double as reconcilers after LDAP syncs).

Design rationale for every privilege choice: [ProxmoxUserQuota-Docs / pool-rbac.md](https://github.com/WilliamLi0623/ProxmoxUserQuota-Docs/blob/main/pool-rbac.md).

## Scripts

| Script | Run on / as | Purpose |
|---|---|---|
| `scripts/00-create-roles.sh` | any cluster node, root | create/refresh roles `UQ-VMUser`, `UQ-Storage`, `UQ-Net`, `UQ-ProxyAudit` |
| `scripts/10-provision-user.sh` | any cluster node, root | create pool `uq-<user>` + ACLs for one user |
| `scripts/30-provision-proxy.sh` | any cluster node, root | create proxy service account `uq-proxy@pve` + API token + ACL, and write the token file for the proxy |
| `scripts/40-provision-storage.sh` | node owning the zpool, root | (P6 defense in depth) per-user ZFS dataset with `zfs quota` + dedicated `zfspool` storage + ACL |
| `scripts/20-verify-p0.sh` | anywhere with `curl` + `python3` | assert the P0 exit criteria via the API |

## Usage

    ./scripts/00-create-roles.sh
    ./scripts/30-provision-proxy.sh -f /etc/uq-proxy/pve-token   # proxy service account + token
    # per user: pool/ACLs, then (optionally) a dedicated hard-quota ZFS storage
    ./scripts/10-provision-user.sh alice@ldap -b vmbr0
    ./scripts/40-provision-storage.sh alice@ldap -q 200          # dataset pool/uq-alice, hard quota 200G
    ./scripts/20-verify-p0.sh https://node1:8006 testuser1@pve 'pw1' testuser2@pve 'pw2' node1

The token file `30-provision-proxy.sh` writes feeds the proxy's `-pve-token-file`; if the proxy is on another host, copy it there and restart `uq-proxy`. Use `--rotate` to regenerate the secret.

`40-provision-storage.sh` is the storage-layer **hard backstop**: ZFS refuses allocation beyond `quota` even if the proxy is bypassed. When using it, grant `UQ-Storage` only on the user's dedicated storage (not a shared one), and set the matching soft cap in `quotas.yaml` (`disk-gib: { uq-<user>: <GiB> }`). Remember to add each user's quota record to the proxy's `quotas.yaml` — a user with no record is default-denied under `-enforce`.

Requirements: PVE 8.x / 9.x. `20-verify-p0.sh` accepts self-signed TLS (`curl -k`) — use against test clusters only.

## License

[MIT](LICENSE)
