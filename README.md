# ProxmoxUserQuota-Cluster

**中文** | [English](README_en.md)

PVE 集群侧脚本：创建最小自定义角色、为用户供给配额资源池与 ACL、验证 P0 退出标准。这些脚本只做「准备与约束」——配额的强制执行由 [ProxmoxUserQuota-Proxy](https://github.com/WilliamLi0623/ProxmoxUserQuota-Proxy) 完成（P4 起）。所有脚本幂等，可反复运行（也用作 LDAP 同步后的对账器）。

每个特权取舍的设计依据见 [ProxmoxUserQuota-Docs / pool-rbac.md](https://github.com/WilliamLi0623/ProxmoxUserQuota-Docs/blob/main/pool-rbac.md)。

## 脚本清单

| 脚本 | 运行位置 / 身份 | 用途 |
|---|---|---|
| `scripts/00-create-roles.sh` | 任一集群节点，root | 创建/刷新角色 `UQ-VMUser`、`UQ-Storage`、`UQ-Net`、`UQ-ProxyAudit` |
| `scripts/10-provision-user.sh` | 任一集群节点，root | 为单个用户创建池 `uq-<user>` 并配置 ACL |
| `scripts/30-provision-proxy.sh` | 任一集群节点，root | 创建代理服务账号 `uq-proxy@pve` + API token + ACL，并写出 token 文件给代理 |
| `scripts/20-verify-p0.sh` | 任何有 `curl` + `python3` 的机器 | 通过 API 断言 P0 退出标准 |

## 用法

    ./scripts/00-create-roles.sh
    ./scripts/10-provision-user.sh alice@ldap -s tank -b vmbr0
    ./scripts/30-provision-proxy.sh -f /etc/uq-proxy/pve-token   # 代理服务账号 + token
    ./scripts/20-verify-p0.sh https://node1:8006 testuser1@pve 'pw1' testuser2@pve 'pw2' node1

`30-provision-proxy.sh` 写出的 token 文件供代理的 `-pve-token-file` 使用；若代理与集群不在同一主机，把该文件拷到代理主机后重启 `uq-proxy`。重新生成密钥用 `--rotate`。

要求：PVE 8.x / 9.x。`20-verify-p0.sh` 接受自签名 TLS（`curl -k`），仅限测试集群使用。

## 许可证

[MIT](LICENSE)
