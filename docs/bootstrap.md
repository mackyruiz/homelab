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
| Authentik OIDC clients | `vault_authentik_proxmox_client_secret`, `vault_authentik_vaultwarden_client_secret`, `vault_authentik_homarr_client_secret`, `vault_authentik_gitea_client_secret`, `vault_authentik_opnsense_client_secret` |
| Vaultwarden | `vault_vaultwarden_admin_password`, `vault_vaultwarden_admin_token_hash` |
| Caddy | `vault_godaddy_api_token` |
| K3s (`group_vars/k3s_cluster/vault.yml`) | `vault_k3s_token` (`openssl rand -hex 32`), `vault_k3s_age_key` (the `AGE-SECRET-KEY-1...` line from `age-keygen`; its public half is `k3s_age_public_key` and `.sops.yaml` in `k3s-fleet`) |

`inventory/host_vars/nas/` holds nas's vaulted sudo password (`nas_become_pass`). The Proxmox OIDC client secret for `sso.tf` is `proxmox_oidc_client_secret` in `terraform.tfvars` and must equal `vault_authentik_proxmox_client_secret`.

## 6. Run playbooks

```bash
cd ansible
ansible-inventory --graph
ansible-playbook playbooks/yarr.yml --check --diff --skip-tags qbittorrent_password
ansible-playbook playbooks/yarr.yml
ansible-playbook playbooks/baseline.yml -l labtest -e ansible_host=<ip>   # Proxmox VMs (common + Docker)
```

`--skip-tags qbittorrent_password` is needed in check mode because the `uri` tasks cannot run. `site.yml` imports baseline, yarr, identity, dns, gitea, pis, ipa_clients, k3s, uptime_kuma in order; read the `dns.yml` warning in the README before running it.

## Notes

- Plex is left unclaimed so you can claim it from its web UI.
- qBittorrent runs through Gluetun (ProtonVPN, WireGuard).
- FlareSolverr listens on 8191 and is reached from Prowlarr at `http://flaresolverr:8191`.
- Homarr is on 7575 and monitors Docker via the mounted socket.
- Sonarr, Radarr, Prowlarr and qBittorrent are published only as `https://<app>.example.com` through Caddy and Authentik forward auth (`yarr_forward_auth_apps`). The apps run with `<APP>__AUTH__METHOD=External`, and `yarr_stack/tasks/sso_firewall.yml` drops direct LAN/IPv6 access to their ports except from Caddy and local containers. qBittorrent trusts only Caddy's IP via its auth-bypass whitelist.

## K3s cluster (Stage 3)

Full description, diagrams and runbooks: [k3s.md](k3s.md). Order from a clean state:

1. Create the age key and the vault file (`group_vars/k3s_cluster/vault.yml`, see the table in step 5). Copy `age-keygen -y` output into `k3s_age_public_key` in `group_vars/k3s_cluster/main.yml`. Store the private key in Vaultwarden as well.
2. `terraform -chdir=terraform/proxmox apply` writes `k3s-1` to `k3s-4` and `*.k3s` DNS records.
3. `ansible-playbook playbooks/pis.yml`, then `ansible-playbook playbooks/k3s.yml`. A Pi with no NOPASSWD sudo rule needs one run of `pis.yml` with a temporary `ansible_become_pass`.
4. Flux creates the `labadmin/k3s-fleet` repo on first bootstrap. After that, workloads change only through Git pushes to that repo.

PATH for the CLIs: `export PATH=~/.local/bin:$PATH` (`kubectl`, `flux`, `sops`, `age`).

## Enrolling hosts in FreeIPA

`scripts/ipa-enroll.sh` enrolls a host or group in FreeIPA (`scripts/ipa-enroll.sh --help`). The default target is the `ipa_clients` group (authentik, vaultwarden, caddy, k3s-1 to k3s-4). A host not in the inventory is enrolled ad hoc, e.g. `scripts/ipa-enroll.sh labtest --ip "$IP"` or `scripts/ipa-enroll.sh pi5.example.com --user ubuntu`.

- Needs SSH key access and sudo on the target, and the target must resolve `freeipa.example.com` (DNS = nas).
- IPA users log in over SSH with IPA-stored keys or Kerberos only (`/etc/ssh/sshd_config.d/00-homelab-ipa-auth.conf`); sudo still asks for the IPA password. Local `labadmin` stays as break-glass.
- Re-imaged hosts re-enroll under the same name (`--force-join`). Remove hosts you destroy with `ipa host-del <fqdn>`.
- The FQDN defaults to `<inventory name>.example.com`; override with `ipa_client_fqdn`.

## Rebuilding SSO (Authentik, Caddy, yarr apps, Homarr, Gitea)

Everything is declarative; no UI step is needed after a rebuild.

1. Secrets. A new OIDC client needs a secret in `ansible/inventory/group_vars/identity/vault.yml`: `scripts/vault-add-secret.sh inventory/group_vars/identity/vault.yml vault_authentik_<app>_client_secret` (refuses to overwrite).
2. DNS: `terraform -chdir=terraform/proxmox apply` (`dns_a_record_set.service` holds `auth`, `sonarr`, `radarr`, `prowlarr`, `qbittorrent`, `homarr`, `gitea`, all pointing at Caddy).
3. In order, from `ansible/`:
   ```bash
   ansible-playbook playbooks/identity.yml     # FreeIPA, Authentik blueprints (homelab, yarr, gitea, opnsense), Caddy
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

## Rebuilding Uptime Kuma

Declarative; no UI step. Secrets in `inventory/group_vars/uptime_kuma_servers/vault.yml`: `vault_uptime_kuma_admin_password` and one 32-hex-char push token per container pushed from yarr (`scripts/vault-add-secret.sh <file> <var> 16`). Add the DNS record (`uptime`), run `identity.yml --limit caddy` for the site, then `uptime_kuma.yml` on nas (creates the admin through the socket.io `setup` event, AutoKuma syncs `static-monitors/*.json`) and `yarr.yml` for the push timer. Kuma history lives in `/opt/uptime-kuma/data`; back it up if you want it kept. Add or remove monitors by editing `uptime_kuma_monitors` and rerunning `uptime_kuma.yml`; removed items are deleted in Kuma.

## OPNsense WebGUI SSO (router, manual)

The Authentik side (`blueprints/opnsense.yaml.j2`, client `opnsense`, only `lab-admins`) is applied by `identity.yml`. The router is not managed by this repo, so the OPNsense side is manual. It uses the third-party plugin [os-sso](https://github.com/MaximeWewer/os-sso) (OPNsense >= 25.7). Community Edition has no built-in OIDC.

1. DNS for the firewall itself. The router's resolver returns NXDOMAIN for `auth.example.com`. Services > Unbound DNS > Overrides > Host Overrides > Add: Host `auth`, Domain `example.com`, Type `A`, IP `10.0.0.34` (Authentik via Caddy). Apply. In System > Settings > General, "Do not use the local DNS service as a nameserver for this system" must be unchecked. If port 53 is Dnsmasq instead of Unbound, add the same host under Services > Dnsmasq DNS & DHCP > Hosts. Use a host override, not a `example.com` forward: a forward would change every `example.com` name for all LAN clients. Proof, from the OPNsense shell (console option 8):
   ```sh
   drill auth.example.com    # 10.0.0.34
   curl -s https://auth.example.com/application/o/opnsense/.well-known/openid-configuration | grep -o '"issuer":"[^"]*"'
   ```
2. Install os-sso (pinned `v2026.10.3`). `opnsense-version` must be >= 25.7. `pkg config ABI` gives `FreeBSD:14:amd64` or `FreeBSD:15:amd64`; use that `N` (14 or 15):
   ```sh
   fetch https://github.com/MaximeWewer/os-sso/releases/download/v2026.10.3/os-sso-devel-2026.10.3-FreeBSD-N.pkg
   sha256 os-sso-devel-2026.10.3-FreeBSD-N.pkg   # abort on mismatch
   pkg add os-sso-devel-2026.10.3-FreeBSD-N.pkg
   configctl webgui restart
   ```
   | ABI | sha256 |
   |---|---|
   | FreeBSD-14 | `e0548e5988729ea9a0c2e2b5b59ad534eaa66cb48bdbbb413b6cace9273391b9` |
   | FreeBSD-15 | `9b718ac55e4bd0a75b82fa7544cf35099884e73d28aee4d256c01d84148c32d5` |
3. System > Access > Servers > Add (everything not listed stays at its default). The secret is `cd ansible && ansible-vault view inventory/group_vars/identity/vault.yml | grep opnsense`.

   | Field | Value |
   |---|---|
   | Descriptive name | `authentik` |
   | Type | OpenID Connect |
   | Issuer URL | `https://auth.example.com/application/o/opnsense/` (trailing slash required) |
   | Client ID | `opnsense` |
   | Client Secret | `vault_authentik_opnsense_client_secret` |
   | Scopes | `openid,email,profile` |
   | Use PKCE (S256) | on |
   | Client authentication method | `auto` |
   | Username claim / Groups claim | `preferred_username` / `groups` |
   | Applies to | `webgui` |
   | Automatic user creation | on (os-sso will not bind to a pre-made account it did not create) |
   | Strict account binding | on |
   | Required groups | `lab-admins` |
   | Deprovision on refused login | on |
   | Group mapping | `lab-admins:admins` |
   | Strict group sync | on |
   | Login button label | `Login with Authentik` |
   | Base URL | `https://10.0.0.1` (must equal `opnsense_gui_url`) |

   Do not change System > Settings > Administration > Authentication Server; os-sso adds its own button.
4. System > Access > SSO Diagnostics, provider `authentik`: redirect URL `https://10.0.0.1/api/sso/oidc/callback`, post-logout URL `https://10.0.0.1/api/sso/oidc/loggedout`, and **Test** succeeds.

Notes:

- Break-glass is local `root` with its password (the normal login form).
- The os-sso config lives in `/conf/config.xml` and survives firmware upgrades, but after a major OPNsense upgrade the package may need `pkg add` again; the SSO button is missing until then.
- If the GUI port or address changes: update `opnsense_gui_url`, rerun `identity.yml -l authentik`, and update the Base URL.
- If login is refused with a "required groups" message (System > Log Files > General), add a scope mapping `scope_name: groups` with `return {"groups": [g.name for g in request.user.all_groups()]}` to the blueprint, attach it to the provider, and set Scopes to `openid,email,profile,groups`.
