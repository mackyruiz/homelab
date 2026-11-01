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

Secrets live in encrypted vault files (every file uses the password from step 4). Each service doc lists its own variables under "Secrets":

| Vault file | Holds secrets for |
|---|---|
| `group_vars/all/vault.yml` | FreeIPA admin password ([FreeIPA](services/freeipa.md#secrets)) |
| `group_vars/identity/vault.yml` | [FreeIPA](services/freeipa.md#secrets), [Authentik](services/authentik.md#secrets), [Vaultwarden](services/vaultwarden.md#secrets), [Caddy](services/caddy.md#secrets), [OPNsense](services/opnsense-sso.md#secrets) |
| `group_vars/yarr/vault.yml` | [yarr stack](services/yarr-stack.md#secrets) |
| `group_vars/uptime_kuma_servers/vault.yml` | [Uptime Kuma](services/uptime-kuma.md#secrets) |
| `group_vars/k3s_cluster/vault.yml` | [K3s](k3s.md) |
| `host_vars/nas/vault.yml` | nas sudo password (`nas_become_pass`, [host baseline](services/host-baseline.md#secrets)) |
| `host_vars/server1/vault.yml` | server1 sudo password (`server1_sudo_pass`, [host baseline](services/host-baseline.md#secrets)) |

## 6. Run playbooks

```bash
cd ansible
ansible-inventory --graph
ansible-playbook playbooks/yarr.yml --check --diff --skip-tags qbittorrent_password   # dry run, see services/yarr-stack.md
ansible-playbook playbooks/yarr.yml
ansible-playbook playbooks/baseline.yml -l labtest -e ansible_host=<ip>   # Proxmox VMs (common + Docker)
```

`site.yml` imports baseline, yarr, identity, dns, gitea, pis, ipa_clients, k3s, uptime_kuma in order. Do not run `dns.yml` (or `site.yml`, which imports it) blindly; see [services/bind9.md](services/bind9.md#operations).

## K3s cluster (Stage 3)

Full description, diagrams and runbooks: [k3s.md](k3s.md). Order from a clean state:

1. Create the age key and the vault file `group_vars/k3s_cluster/vault.yml` with two variables: `vault_k3s_token` (`openssl rand -hex 32`) and `vault_k3s_age_key` (the `AGE-SECRET-KEY-1...` line from `age-keygen`; its public half is `backup_age_public_key` and `.sops.yaml` in `k3s-fleet`). Copy `age-keygen -y` output into `backup_age_public_key` in `group_vars/all/main.yml`. Store the private key in Vaultwarden as well.
2. `terraform -chdir=terraform/proxmox apply` writes `k3s-1` to `k3s-4` and `*.k3s` DNS records.
3. `ansible-playbook playbooks/pis.yml`, then `ansible-playbook playbooks/k3s.yml`. A Pi with no NOPASSWD sudo rule needs one run of `pis.yml` with a temporary `ansible_become_pass`.
4. Flux creates the `labadmin/k3s-fleet` repo on first bootstrap. After that, workloads change only through Git pushes to that repo.

PATH for the CLIs: `export PATH=~/.local/bin:$PATH` (`kubectl`, `flux`, `sops`, `age`).

## Per-service runbooks

Rebuild, recovery and day-2 steps for each service: [services/README.md](services/README.md).
