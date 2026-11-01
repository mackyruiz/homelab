# Host baseline (shared roles)

The roles every managed host gets (`common`, `docker`, `nfs_mount`, `internal_dns`), documented once so the service docs can link here instead of repeating them.

| | |
|---|---|
| Host | All Proxmox VMs, yarr, the Pis and nas (per role, see below) |
| Address / URL | n/a |
| Ports | 22/tcp open by default (`firewall_allowed_tcp_ports`) |
| Software | OS packages; Docker CE; `nfs-common`; systemd-resolved drop-in |
| Data | `/mnt/pishare` (Pis), `/srv/media` (yarr) mount points |
| Deployed by | `baseline.yml`, `yarr.yml`, `identity.yml`, `gitea.yml`, `pis.yml` (all imported by `site.yml`) |
| Depends on | [proxmox.md](proxmox.md) (creates the VMs), [bind9.md](bind9.md) (target of `internal_dns`), [nas-storage.md](nas-storage.md) (NFS server) |
| Used by | [freeipa.md](freeipa.md), [authentik.md](authentik.md), [vaultwarden.md](vaultwarden.md), [caddy.md](caddy.md), [yarr-stack.md](yarr-stack.md), [gitea.md](gitea.md), [uptime-kuma.md](uptime-kuma.md), [../k3s.md](../k3s.md) |

## Purpose

This is not one service. It is the common layer: SSH hardening, firewall, automatic updates, Docker, NFS mounts and internal DNS routing that every host gets before its own service role runs.

## Configuration

### Files

| Path | What it sets |
|---|---|
| [`ansible/roles/common/tasks/main.yml`](../../ansible/roles/common/tasks/main.yml) | Timezone, packages, `qemu-guest-agent`, admin user and keys, sshd hardening, fail2ban |
| [`ansible/roles/common/tasks/packages_Debian.yml`](../../ansible/roles/common/tasks/packages_Debian.yml), [`packages_RedHat.yml`](../../ansible/roles/common/tasks/packages_RedHat.yml) | Base packages per OS family |
| [`ansible/roles/common/tasks/hardening_Debian.yml`](../../ansible/roles/common/tasks/hardening_Debian.yml) | unattended-upgrades, UFW |
| [`ansible/roles/common/tasks/hardening_RedHat.yml`](../../ansible/roles/common/tasks/hardening_RedHat.yml) | dnf-automatic, firewalld |
| [`ansible/roles/docker/tasks/main.yml`](../../ansible/roles/docker/tasks/main.yml), [`defaults/main.yml`](../../ansible/roles/docker/defaults/main.yml) | Docker CE apt repo, packages, docker group |
| [`ansible/roles/nfs_mount/tasks/main.yml`](../../ansible/roles/nfs_mount/tasks/main.yml), [`defaults/main.yml`](../../ansible/roles/nfs_mount/defaults/main.yml) | NFS client package and the `nfs_mounts` list |
| [`ansible/roles/internal_dns/tasks/main.yml`](../../ansible/roles/internal_dns/tasks/main.yml) | systemd-resolved drop-in |
| [`ansible/playbooks/baseline.yml`](../../ansible/playbooks/baseline.yml), [`pis.yml`](../../ansible/playbooks/pis.yml), [`site.yml`](../../ansible/playbooks/site.yml) | Which roles run where |
| [`ansible/inventory/hosts.yml`](../../ansible/inventory/hosts.yml) | Host groups |
| [`ansible/inventory/group_vars/all/main.yml`](../../ansible/inventory/group_vars/all/main.yml), [`yarr/main.yml`](../../ansible/inventory/group_vars/yarr/main.yml), [`pis/main.yml`](../../ansible/inventory/group_vars/pis/main.yml) | Variables below |

### Roles

**`common`** (RedHat and Debian variants)

- Sets the timezone, installs base packages (ca-certificates, curl, gnupg, fail2ban, qemu-guest-agent, acl) and keeps `qemu-guest-agent` enabled.
- Creates the admin user `labadmin` (groups `sudo` on Debian, `wheel` on RedHat) and authorizes `ssh_public_keys`.
- Sets `PermitRootLogin no` and `PasswordAuthentication no` in `sshd_config` and restarts ssh.
- Enables fail2ban (`fail2ban_enabled`).
- Debian: `unattended-upgrades` (`unattended_upgrades_enabled`), and UFW with incoming deny, outgoing allow and `firewall_allowed_tcp_ports` open.
- RedHat: EPEL, `dnf-automatic` with `apply_updates = yes`, and firewalld with `firewall_allowed_tcp_ports` opened.

**`docker`**

- Adds the Docker CE apt repository and installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`; enables the service and adds `labadmin` to the `docker` group.

**`nfs_mount`**

- Installs `nfs-common` (the Pis also get `nfs4-acl-tools`), creates each mount point and mounts every entry of `nfs_mounts`.
- yarr mounts `10.0.0.225:/tank/plex` on `/srv/media` with `x-systemd.automount`.
- The Pis mount `10.0.0.225:/tank/pishare` on `/mnt/pishare`.
- Server side: [nas-storage.md](nas-storage.md).

**`internal_dns`**

- Writes `/etc/systemd/resolved.conf.d/internal-domain.conf` with `DNS=<internal_dns_server>` and `Domains=~example.com`, then restarts systemd-resolved if it changed.
- It exists because the router's IPv6 RA advertises a resolver that answers NXDOMAIN for the internal records, so the internal domain goes to nas ([bind9.md](bind9.md)) only.

### Which playbook applies which role

| Playbook | Hosts | Roles / tasks |
|---|---|---|
| `baseline.yml` | `proxmox_vms` | `common` |
| `baseline.yml` | `proxmox_vms:!freeipa_servers` | `docker` |
| `yarr.yml` | `yarr` | `common`, `docker`, `nfs_mount`, `internal_dns`, then `yarr_stack` ([yarr-stack.md](yarr-stack.md)) |
| `identity.yml` | `freeipa_servers` | `common`, then `freeipa_server` |
| `identity.yml` | authentik, vaultwarden, caddy | `common`, `docker`, `freeipa_client`, then the service role |
| `gitea.yml` | `gitea_servers` (nas) | `internal_dns`, then `gitea` |
| `pis.yml` | `pis` | pre-tasks: NOPASSWD sudo rule for the admin user, apt update, `apt dist-upgrade`; role `nfs_mount` |

### Variables

| Variable | Defined in | Value / meaning |
|---|---|---|
| `timezone` | `group_vars/all/main.yml` | `America/Los_Angeles` |
| `admin_user` | `group_vars/all/main.yml` | `labadmin` |
| `ssh_public_keys` | `group_vars/all/main.yml` | three ed25519 keys (workstation, laptop, server1) |
| `firewall_allowed_tcp_ports` | `group_vars/all/main.yml`, `yarr/main.yml` | `[22]`; on yarr also 32400, 8191 and 7575 |
| `unattended_upgrades_enabled`, `fail2ban_enabled` | `group_vars/all/main.yml` | both `true` |
| `internal_dns_server` | `group_vars/all/main.yml` | `ansible_host` of the first `dns_servers` host (nas, 10.0.0.225) |
| `internal_dns_domain` | `group_vars/all/main.yml` | `example.com` |
| `nfs_mounts` | `group_vars/yarr/main.yml`, `group_vars/pis/main.yml` | yarr: `/tank/plex` to `/srv/media` (`defaults,_netdev,nofail,x-systemd.automount,x-systemd.requires=network-online.target`); Pis: `/tank/pishare` to `/mnt/pishare` (`rw,sync`, mode 0777) |
| `docker_apt_release_channel` | `roles/docker/defaults/main.yml` | `stable` |

### Secrets

Host sudo passwords for hosts without NOPASSWD sudo.

| Vault variable | Vault file | Used for |
|---|---|---|
| `nas_become_pass` | `inventory/host_vars/nas/vault.yml` | `ansible_become_pass` for nas (set in `host_vars/nas/main.yml`) |
| `server1_sudo_pass` | `inventory/host_vars/server1/vault.yml` | `ansible_become_pass` for server1 (set in `host_vars/server1/main.yml`) |

## How it works

Every playbook that provisions a host starts with these roles, so a fresh VM comes out of cloud-init, receives SSH hardening, firewall and updates from `common`, then Docker if it will run containers (FreeIPA is excluded from `docker`). Service roles then add the ports they need through their own firewall tasks or `firewall_allowed_tcp_ports`.

`internal_dns` only runs on hosts whose containers must resolve internal names (yarr, nas). The Pis get the same effect through NetworkManager (`ipv4.dns` set in the k3s role's network tasks, see [../k3s.md](../k3s.md)).

## Operations

Apply the baseline to all Proxmox VMs:

```bash
cd ansible
ansible-playbook playbooks/baseline.yml
```

Verify: `ssh labadmin@<host>` works with a key; `ufw status` (Debian) or `firewall-cmd --list-ports` (RedHat) shows only the expected ports; on a host with `internal_dns`, `resolvectl status` lists `~example.com` routed to 10.0.0.225.

Recovery: roles are idempotent; re-run the playbook. The Pis' NOPASSWD sudo rule is written by `pis.yml` itself.

Known gaps:

- `server1` is in the inventory (`server1.example.com`, with `server1_sudo_pass`) but no playbook applies a role to it.
