# Bootstrap

Run all commands from the repo root unless noted. Prerequisites: `terraform >= 1.6`, `ansible` (with `ansible-galaxy`), SSH access to the Proxmox node.

## 1. Proxmox API token and snippets

1. Create an API token for `root@pam` (or a dedicated automation user). You need `proxmox_api_token_id` (e.g. `root@pam!terraform`) and `proxmox_api_token_secret`.
2. The provider SSHes to the node for snippet uploads and disk imports. Record the host key once: `ssh -o StrictHostKeyChecking=accept-new root@10.0.0.60 true`.
3. In Proxmox, enable the `Snippets` content type on the `local` datastore (Datacenter > Storage > local). VM cloud-init vendor data installs `qemu-guest-agent` from a snippet.

API endpoint: `https://10.0.0.60:8006/api2/json`, node `pve1`.

## 2. Terraform variables

```bash
cp terraform/proxmox/terraform.tfvars.example terraform/proxmox/terraform.tfvars
$EDITOR terraform/proxmox/terraform.tfvars   # token id/secret, ssh username, private key path
```

`terraform.tfvars` is gitignored. It holds only credentials and environment. VM shapes live in `terraform/proxmox/main.tf`.

## 3. Apply Terraform

```bash
terraform -chdir=terraform/proxmox init
terraform -chdir=terraform/proxmox plan
terraform -chdir=terraform/proxmox apply
```

Maintains: Ubuntu 24.04 template (106), yarr VM (107), Debian 13 template (9001). On the existing lab, 106 and 107 were adopted with `import` blocks; the modules use `lifecycle.ignore_changes` for attributes the API does not return (`url`, `source_raw`, `disk[0].file_id`, `clone`).

## 4. Ansible vault password

```bash
umask 077; openssl rand -base64 32 > ansible/.vault_pass   # or copy the existing one
```

`ansible/.vault_pass` is gitignored; `ansible.cfg` points at it. Every vault file uses the same password.

## 5. Ansible collections and secrets

```bash
cd ansible
ansible-galaxy collection install -r collections/requirements.yml
ansible-vault create inventory/group_vars/yarr/vault.yml   # only on a new setup
```

Variables in `inventory/group_vars/yarr/vault.yml` and the `/opt/yarr/.env` key each feeds:

| `.env` key                         | Vault variable                                                |
|------------------------------------|---------------------------------------------------------------|
| `HOMARR_SECRET_ENCRYPTION_KEY`     | `vault_homarr_secret_encryption_key` (`openssl rand -hex 32`) |
| `WIREGUARD_PRIVATE_KEY`            | `vault_gluetun_wireguard_private_key`                         |
| `WIREGUARD_ADDRESSES`              | `vault_gluetun_wireguard_addresses`                           |
| `OPENVPN_USER`                     | `vault_gluetun_openvpn_user`                                  |
| `OPENVPN_PASSWORD`                 | `vault_gluetun_openvpn_password`                              |
| `PLEX_CLAIM`                       | `vault_plex_claim_token`                                      |
| `WATCHTOWER_NOTIFICATION_URL`      | `vault_watchtower_notification_url`                           |
| (qBittorrent Web UI, user `admin`) | `vault_qbittorrent_webui_password`                            |

Identity and SSO secrets live in `inventory/group_vars/identity/vault.yml` (the yarr and Gitea roles read the Authentik client secrets from it through `hostvars`):

| Purpose | Vault variables |
|---------|-----------------|
| FreeIPA | `vault_ipa_admin_password`, `vault_ipa_ds_password`, `vault_ipa_user_password`, `vault_ipa_authentik_bind_password` |
| Authentik | `vault_authentik_secret_key`, `vault_authentik_pg_password`, `vault_authentik_bootstrap_password`, `vault_authentik_bootstrap_token` |
| Authentik OIDC clients | `vault_authentik_proxmox_client_secret`, `vault_authentik_vaultwarden_client_secret`, `vault_authentik_homarr_client_secret`, `vault_authentik_gitea_client_secret` |
| Vaultwarden | `vault_vaultwarden_admin_password`, `vault_vaultwarden_admin_token_hash` |
| Caddy | `vault_godaddy_api_token` |

`inventory/host_vars/nas/` holds nas's vaulted sudo password (`nas_become_pass`). The Proxmox OIDC client secret for `sso.tf` is `proxmox_oidc_client_secret` in `terraform.tfvars` and must equal `vault_authentik_proxmox_client_secret`.

## 6. Run playbooks

```bash
cd ansible
ansible-inventory --graph
ansible-playbook playbooks/yarr.yml --check --diff --skip-tags qbittorrent_password
ansible-playbook playbooks/yarr.yml
ansible-playbook playbooks/baseline.yml -l labtest -e ansible_host=<ip>   # Proxmox VMs (common + Docker)
```

`--skip-tags qbittorrent_password` is needed in check mode because the `uri` tasks cannot run. `site.yml` imports baseline, yarr, identity, dns, gitea, pis, ipa_clients in order; read the `dns.yml` warning in the README before running it.

## Notes

- Plex is left unclaimed so you can claim it from its web UI.
- qBittorrent runs through Gluetun (ProtonVPN, WireGuard).
- FlareSolverr listens on 8191 and is reached from Prowlarr at `http://flaresolverr:8191`.
- Homarr is on 7575 and monitors Docker via the mounted socket.
- Sonarr, Radarr, Prowlarr and qBittorrent are published only as `https://<app>.example.com` through Caddy and Authentik forward auth (`yarr_forward_auth_apps`). The apps run with `<APP>__AUTH__METHOD=External`, and `yarr_stack/tasks/sso_firewall.yml` drops direct LAN/IPv6 access to their ports except from Caddy and local containers. qBittorrent trusts only Caddy's IP via its auth-bypass whitelist.

## Enrolling hosts in FreeIPA

`scripts/ipa-enroll.sh` enrolls a host or group in FreeIPA (`scripts/ipa-enroll.sh --help`). The default target is the `ipa_clients` group (authentik, vaultwarden, caddy, pi1-pi4). A host not in the inventory is enrolled ad hoc, e.g. `scripts/ipa-enroll.sh labtest --ip "$IP"` or `scripts/ipa-enroll.sh pi5.example.com --user ubuntu`.

- Needs SSH key access and sudo on the target, and the target must resolve `freeipa.example.com` (DNS = nas).
- IPA users log in over SSH with IPA-stored keys or Kerberos only (`/etc/ssh/sshd_config.d/00-homelab-ipa-auth.conf`); sudo still asks for the IPA password. Local `labadmin` stays as break-glass.
- Re-imaged hosts re-enroll under the same name (`--force-join`). Remove hosts you destroy with `ipa host-del <fqdn>`.
- The FQDN defaults to `<inventory name>.example.com`; override with `ipa_client_fqdn` (pi1 is `pi.example.com`).

## Rebuilding SSO (Authentik, Caddy, yarr apps, Homarr, Gitea)

Everything is declarative; no UI step is needed after a rebuild.

1. Secrets. A new OIDC client needs a secret in `ansible/inventory/group_vars/identity/vault.yml`: `scripts/vault-add-secret.sh inventory/group_vars/identity/vault.yml vault_authentik_<app>_client_secret` (refuses to overwrite).
2. DNS: `terraform -chdir=terraform/proxmox apply` (`dns_a_record_set.service` holds `auth`, `sonarr`, `radarr`, `prowlarr`, `qbittorrent`, `homarr`, `gitea`, all pointing at Caddy).
3. In order, from `ansible/`:
   ```bash
   ansible-playbook playbooks/identity.yml     # FreeIPA, Authentik blueprints (homelab, yarr, gitea), Caddy
   ansible-playbook playbooks/yarr.yml         # internal DNS, apps with External auth, SSO firewall, Homarr OIDC + admin group
   ansible-playbook playbooks/gitea.yml        # internal DNS, Gitea admin, ROOT_URL, Authentik OIDC source
   ```
   Caddy needs up to ~3 minutes for Let's Encrypt certificates on first start.
4. If `https://<app>.example.com` answers 404 or "no provider" from `/outpost.goauthentik.io/auth/caddy`, the embedded outpost has not refreshed (5 minute interval): `ssh labadmin@10.0.0.32 sudo docker compose -p authentik -f /opt/authentik/docker-compose.yml restart server`.

How the account mapping is declared:

- **Forward-auth apps** (Sonarr, Radarr, Prowlarr, qBittorrent): `yarr_forward_auth_apps` in `group_vars/all`. Any Authentik user may open them.
- **Admin group**: `sso_admin_group` (`lab-admins`, a FreeIPA group). Gitea maps it to administrators through the OIDC source (`--admin-group`). Homarr gets a group of the same name with the `admin` permission from `yarr_stack/files/homarr-seed-admin-group.js`, because Homarr places OIDC users into groups by name.
- **Gitea**: `gitea_username_map` (Authentik username -> local Gitea username). The `Gitea: profile` scope mapping in `blueprints/gitea.yaml.j2` returns the mapped name as `nickname`, and `ACCOUNT_LINKING=auto` links the first SSO login to the local account of that name. `gitea_admin_user` is created on a fresh install with a random password; recover it with `docker exec -u git gitea gitea admin user change-password --username labadmin --password <new>` on nas.
- **Homarr**: `labadmin` (credentials) stays as break-glass; `labuser` is created by the first SSO login and lands in `lab-admins`.

What a rebuild does not restore: Homarr boards/apps/integrations (back up `/opt/yarr/config/homarr`), and the first-run Homarr onboarding user on a brand-new `/opt/yarr/config/homarr` (restore the directory, or click through onboarding once).
