# FreeIPA

FreeIPA is the lab's identity source of truth: Linux users, groups, SSH keys, sudo and host-based access rules, and the LDAP directory that [Authentik](authentik.md) reads.

| | |
|---|---|
| Host | VM 301 `freeipa` (AlmaLinux, 2 cores, 4096 MB, 32 GB), 10.0.0.31 |
| Address / URL | `freeipa.example.com`; web UI `https://freeipa.example.com/ipa/ui/`; realm `EXAMPLE.COM`, domain `example.com` |
| Ports | firewalld service `freeipa-4` is opened; monitored: web UI, 636 (LDAPS), 88 (Kerberos) |
| Software | `ipa-server`, `python3-ldap` (AlmaLinux packages, no version pin); `freeipa-client` / `ipa-client` on enrolled hosts |
| Data | FreeIPA package defaults on the VM (not set by this repo); `/etc/ipa/default.conf` marks the install as done |
| Deployed by | `playbooks/identity.yml` (roles `common`, `freeipa_server`); clients: `playbooks/ipa_clients.yml` (role `freeipa_client`) and `scripts/ipa-enroll.sh` |
| Depends on | [bind9](bind9.md) (DNS records and SRV records), [Proxmox](proxmox.md) (VM), [host-baseline](host-baseline.md) |
| Used by | [Authentik](authentik.md) (LDAP source), [Vaultwarden](vaultwarden.md), [Caddy](caddy.md) and the K3s nodes (enrolled as clients, see [k3s.md](../k3s.md)), [Uptime Kuma](uptime-kuma.md) (monitors it) |

## Purpose

FreeIPA holds every human account in the lab: users, the admin group `lab-admins`, their SSH public keys, and the access policy for logging in to enrolled Linux hosts. Authentik syncs users and groups from it (it is Authentik's LDAP source), so one account works for SSH, sudo and every SSO application. The admin group name is the variable `sso_admin_group`; Gitea, Homarr and OPNsense map it to administrators.

## Configuration

### Files

| Path | What it sets |
|------|--------------|
| [`ansible/roles/freeipa_server/tasks/main.yml`](../../ansible/roles/freeipa_server/tasks/main.yml) | Hostname and `/etc/hosts` pinning, package install, firewalld, `ipa-server-install`, admin group, users, HBAC and sudo rules, Authentik bind account, SSH policy |
| [`ansible/roles/freeipa_server/templates/hosts.redhat.tmpl.j2`](../../ansible/roles/freeipa_server/templates/hosts.redhat.tmpl.j2) | Replacement for cloud-init's `/etc/cloud/templates/hosts.redhat.tmpl` (maps the FQDN to the LAN address) |
| [`ansible/roles/freeipa_client/tasks/main.yml`](../../ansible/roles/freeipa_client/tasks/main.yml) | Client enrollment (asserts, DNS check, package install, `ipa-client-install`) |
| [`ansible/roles/freeipa_client/tasks/sshd.yml`](../../ansible/roles/freeipa_client/tasks/sshd.yml) | `/etc/ssh/sshd_config.d/00-homelab-ipa-auth.conf`, applied on clients and on the server |
| [`ansible/roles/freeipa_client/defaults/main.yml`](../../ansible/roles/freeipa_client/defaults/main.yml) | Default `ipa_client_fqdn` |
| [`ansible/roles/freeipa_client/handlers/main.yml`](../../ansible/roles/freeipa_client/handlers/main.yml) | Restarts `sshd` (RedHat) or `ssh` (Debian) when the SSH policy changes |
| [`ansible/playbooks/identity.yml`](../../ansible/playbooks/identity.yml) | Applies `common` and `freeipa_server` to `freeipa_servers`, then enrolls the Authentik, Vaultwarden and Caddy VMs |
| [`ansible/playbooks/ipa_clients.yml`](../../ansible/playbooks/ipa_clients.yml) | Applies `freeipa_client` to `ipa_enroll_target` (default group `ipa_clients`) |
| [`scripts/ipa-enroll.sh`](../../scripts/ipa-enroll.sh) | Wrapper around `ipa_clients.yml` for a host, a group, or a host not in the inventory |
| [`ansible/inventory/group_vars/identity/main.yml`](../../ansible/inventory/group_vars/identity/main.yml) | `ipa_base_dn`, `ipa_admin_group`, `ipa_users` |
| [`ansible/inventory/group_vars/all/main.yml`](../../ansible/inventory/group_vars/all/main.yml) | `ipa_domain`, `ipa_realm`, `ipa_server_fqdn`, `sso_admin_group` |
| [`terraform/proxmox/dns.tf`](../../terraform/proxmox/dns.tf) | DNS records that point clients at FreeIPA (see [How it works](#how-it-works)) |
| [`terraform/proxmox/identity.tf`](../../terraform/proxmox/identity.tf) | VM 301 (`local.identity_vms.freeipa`), see [proxmox](proxmox.md) |

### Variables

| Variable | Defined in | Value / meaning |
|----------|------------|-----------------|
| `ipa_domain` | `group_vars/all/main.yml` | `example.com` |
| `ipa_realm` | `group_vars/all/main.yml` | `EXAMPLE.COM` |
| `ipa_server_fqdn` | `group_vars/all/main.yml` | `freeipa.example.com` |
| `ipa_base_dn` | `group_vars/identity/main.yml` | `dc=example,dc=com` |
| `ipa_admin_group` | `group_vars/identity/main.yml` | `{{ sso_admin_group }}` |
| `sso_admin_group` | `group_vars/all/main.yml` | `lab-admins`; members become admins in Gitea, Homarr and OPNsense |
| `ipa_users` | `group_vars/identity/main.yml` | List of users to create. Currently one: `labuser` |
| `ssh_public_keys` | `group_vars/all/main.yml` | Public keys stored on each IPA user (`sshpubkey`); the same list goes to the local `labadmin` account |
| `ipa_client_fqdn` | `roles/freeipa_client/defaults/main.yml` | Name a client enrolls under: the inventory name if it contains a dot, else `<inventory name>.<ipa_domain>`. Overridden per host (`k3s-1` sets it in `inventory/hosts.yml`) or with `--fqdn` |
| `ipa_enroll_target` | `playbooks/ipa_clients.yml` | Host pattern the playbook runs against; default `ipa_clients` (set by `scripts/ipa-enroll.sh`) |

### Secrets

| Vault variable | Vault file | Used for |
|----------------|------------|----------|
| `vault_ipa_admin_password` | `group_vars/all/vault.yml` | IPA `admin` password: server install, all `ipa*` module calls, and `ipa-client-install` on every enrolled host. It is in the `all` vault, not the `identity` vault, because clients outside the `identity` group need it |
| `vault_ipa_ds_password` | `group_vars/identity/vault.yml` | Directory Manager password (`--ds-password`, and the LDAP bind that creates the Authentik account) |
| `vault_ipa_user_password` | `group_vars/identity/vault.yml` | Initial password for each user in `ipa_users` (`update_password: on_create`) |
| `vault_ipa_authentik_bind_password` | `group_vars/identity/vault.yml` | Password of the `uid=authentik` bind account; [Authentik](authentik.md) reads it as `AUTHENTIK_FREEIPA_BIND_PASSWORD` |

The sources give no generation instructions for these four values.

## How it works

**Server install.** `ipa-server-install` refuses an FQDN that maps to 127.0.0.1, which the stock cloud-init hosts template produces. The role therefore stops cloud-init rewriting the hostname (`preserve_hostname: true`), pins the hosts template, writes `/etc/hosts` with the LAN address for `freeipa.example.com`, sets the hostname, installs `ipa-server`, opens the firewalld service `freeipa-4`, and runs `ipa-server-install --unattended` with the realm, domain, FQDN and the two vault passwords. The install task is skipped once `/etc/ipa/default.conf` exists. FreeIPA's own DNS is not set up; DNS comes from [bind9](bind9.md).

**Access policy.** After the install the role creates:

- the group `lab-admins` (`sso_admin_group`) and the users from `ipa_users`, with `ssh_public_keys` and a password expiry pushed to 2099-12-31. An admin-set password would otherwise expire at first use and break the LDAP bind.
- the HBAC rule `lab-admins-all` (members of `lab-admins`, all hosts, all services), and it disables the default `allow_all` rule, so only `lab-admins` can log in to enrolled hosts.
- the sudo rule `lab-admins-all` (all hosts, all commands, any run-as user and group).
- the Authentik LDAP bind account `uid=authentik,cn=sysaccounts,cn=etc,dc=example,dc=com` (password expiry 2038, no idle timeout).

**SSH policy.** `freeipa_client/tasks/sshd.yml` writes `/etc/ssh/sshd_config.d/00-homelab-ipa-auth.conf` (`KbdInteractiveAuthentication no`, `PasswordAuthentication no`). It sorts before FreeIPA's `04-ipa.conf` and sshd keeps the first value, so IPA users log in with IPA-stored keys or Kerberos only. The role then asserts with `sshd -T` that the policy is effective. The server applies the same task.

**DNS records.** Terraform writes these into the zone served by [bind9](bind9.md), all pointing at FreeIPA:

| Record | Value |
|--------|-------|
| `freeipa` A (from `identity_host`) | 10.0.0.31 |
| `ipa-ca` A | 10.0.0.31 |
| SRV `_ldap._tcp` | port 389, target `freeipa.example.com.` |
| SRV `_kerberos._tcp`, `_kerberos._udp`, `_kerberos-master._tcp`, `_kerberos-master._udp` | port 88, same target |
| SRV `_kpasswd._tcp`, `_kpasswd._udp` | port 464, same target |
| TXT `_kerberos` | `EXAMPLE.COM` |

**Clients.** The role `freeipa_client` runs on the group `ipa_clients` (authentik, vaultwarden, caddy, k3s-1 to k3s-4). It first asserts the platform (Debian or RedHat family) and that `ipa_client_fqdn` is a lowercase FQDN under `example.com`. It then checks that `freeipa.example.com` resolves and fails with a pointer to the DNS server if it does not. It installs `freeipa-client` (Debian) or `ipa-client` (RedHat), and runs `ipa-client-install --unattended --mkhomedir --no-ntp --no-dns-sshfp --force-join` as `admin`. The install task is skipped once `/etc/ipa/default.conf` exists. Finally it applies the SSH policy above.

`identity.yml` enrolls the Authentik, Vaultwarden and Caddy VMs as part of its second play. `ipa_clients.yml` and `scripts/ipa-enroll.sh` enroll any host or group later; the K3s Pis are enrolled that way.

**Monitoring.** [Uptime Kuma](uptime-kuma.md) checks the web UI (TLS verification off, because the IPA CA is not in Kuma's trust store), LDAPS on 636 and Kerberos on 88.

## Operations

Deploy or rebuild (from `ansible/`):

```bash
ansible-playbook playbooks/identity.yml     # FreeIPA server, enrollment of authentik/vaultwarden/caddy, then Authentik, Vaultwarden, Caddy
```

The FreeIPA VM is created by Terraform ([proxmox](proxmox.md)) and its DNS records come from `terraform apply`. See [bootstrap.md](../bootstrap.md) for the whole-lab order.

Verify: the Kuma monitors `FreeIPA web UI`, `FreeIPA LDAPS` and `FreeIPA Kerberos` are green, or `getent hosts freeipa.example.com` resolves from an enrolled host.

### Enrolling hosts in FreeIPA

`scripts/ipa-enroll.sh` enrolls a host or group in FreeIPA (`scripts/ipa-enroll.sh --help`). The default target is the `ipa_clients` group (authentik, vaultwarden, caddy, k3s-1 to k3s-4). A host not in the inventory is enrolled ad hoc, e.g. `scripts/ipa-enroll.sh labtest --ip "$IP"` or `scripts/ipa-enroll.sh pi5.example.com --user ubuntu`.

- Needs SSH key access and sudo on the target, and the target must resolve `freeipa.example.com` (DNS = nas).
- IPA users log in over SSH with IPA-stored keys or Kerberos only (`/etc/ssh/sshd_config.d/00-homelab-ipa-auth.conf`); sudo still asks for the IPA password. Local `labadmin` stays as break-glass.
- Re-imaged hosts re-enroll under the same name (`--force-join`). Remove hosts you destroy with `ipa host-del <fqdn>`.
- The FQDN defaults to `<inventory name>.example.com`; override with `ipa_client_fqdn`.

### Recovery

- A re-imaged client re-enrolls with the same command; `--force-join` replaces its old host entry.
- If a client cannot resolve `freeipa.example.com`, the role fails with a message naming the DNS server (nas). Fix the host's DNS (see [bind9](bind9.md) and [host-baseline](host-baseline.md)) and rerun.
