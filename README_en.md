# ProxmoxUserQuota-Cluster

[中文](README.md) | **English**

PVE cluster-side scripts: create the minimal custom roles, provision per-user quota pools/ACLs, and verify the P0 exit criteria. These scripts only *prepare and constrain* the cluster — quota enforcement itself is done by [ProxmoxUserQuota-Proxy](https://github.com/WilliamLi0623/ProxmoxUserQuota-Proxy) (from P4). All scripts are idempotent and safe to re-run (they double as reconcilers after LDAP syncs).

Design rationale for every privilege choice: [ProxmoxUserQuota-Docs / pool-rbac.md](https://github.com/WilliamLi0623/ProxmoxUserQuota-Docs/blob/main/pool-rbac.md).

## Scripts

| Script | Run on / as | Purpose |
|---|---|---|
| `scripts/00-create-roles.sh` | any cluster node, root | create/refresh roles `UQ-VMUser`, `UQ-Storage`, `UQ-Net`, `UQ-ProxyAudit` |
| `scripts/10-provision-user.sh` | any cluster node, root | create pool `uq-<user>` + ACLs for one user |
| `scripts/20-verify-p0.sh` | anywhere with `curl` + `python3` | assert the P0 exit criteria via the API |

## Usage

    ./scripts/00-create-roles.sh
    ./scripts/10-provision-user.sh alice@ldap -s tank -b vmbr0
    ./scripts/20-verify-p0.sh https://node1:8006 testuser1@pve 'pw1' testuser2@pve 'pw2' node1

Requirements: PVE 8.x / 9.x. `20-verify-p0.sh` accepts self-signed TLS (`curl -k`) — use against test clusters only.

## License

[MIT](LICENSE)
