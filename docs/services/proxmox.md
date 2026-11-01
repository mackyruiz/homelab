# Proxmox host and Terraform

The Proxmox host `pve1` runs every VM in the lab; Terraform builds its cloud-image templates and VMs and wires Proxmox login to Authentik.

| | |
|---|---|
| Host | pve1 (Proxmox VE) |
| Address / URL | 10.0.0.60, API `https://10.0.0.60:8006/api2/json` |
| Ports | 8006 (API and web UI) |
| Software | Terraform `>= 1.6.0`; providers `bpg/proxmox ~> 0.66`, `hashicorp/dns ~> 3.4` |
| Data | `terraform/proxmox/terraform.tfstate` (local, gitignored) |
| Deployed by | `terraform -chdir=terraform/proxmox apply` (modules `proxmox-template`, `proxmox-vm`) |
| Depends on | [authentik.md](authentik.md) (OIDC login), [bind9.md](bind9.md) (DNS records are written from the same config) |
| Used by | [freeipa.md](freeipa.md), [authentik.md](authentik.md), [vaultwarden.md](vaultwarden.md), [caddy.md](caddy.md), [yarr-stack.md](yarr-stack.md) (their VMs); [host-baseline.md](host-baseline.md) (configures the VMs afterwards) |

## Purpose

Terraform in `terraform/proxmox/` is the single source for the Proxmox templates and the VMs the lab runs on. Ansible configures the VMs after Terraform creates them. The same root module also writes DNS records to bind9 ([bind9.md](bind9.md)) and registers Authentik as a Proxmox login realm.

## Configuration

### Files

| Path | What it sets |
|---|---|
| [`terraform/proxmox/main.tf`](../../terraform/proxmox/main.tf) | Templates 106 (Ubuntu), 9001 (Debian), 9002 (AlmaLinux); VM 107 `yarr`; optional VM 900 `labtest` |
| [`terraform/proxmox/identity.tf`](../../terraform/proxmox/identity.tf) | `locals.identity_vms` and the identity VMs 301-304 |
| [`terraform/proxmox/sso.tf`](../../terraform/proxmox/sso.tf) | OpenID realm `authentik`, user `labuser@authentik`, `Administrator` ACL |
| [`terraform/proxmox/dns.tf`](../../terraform/proxmox/dns.tf) | bind9 records (see [bind9.md](bind9.md#records-terraform-writes)) |
| [`terraform/proxmox/variables.tf`](../../terraform/proxmox/variables.tf) | All input variables |
| [`terraform/proxmox/outputs.tf`](../../terraform/proxmox/outputs.tf) | Template and VM IDs, `yarr_ipv4`, `labtest_ipv4` |
| [`terraform/proxmox/versions.tf`](../../terraform/proxmox/versions.tf) | Terraform and provider version constraints |
| [`terraform/proxmox/providers.tf`](../../terraform/proxmox/providers.tf) | `proxmox` provider (API token, SSH for disk import) and `dns` provider (TSIG update) |
| [`terraform/modules/proxmox-template/main.tf`](../../terraform/modules/proxmox-template/main.tf) | Downloads a cloud image and builds a template VM |
| [`terraform/modules/proxmox-vm/main.tf`](../../terraform/modules/proxmox-vm/main.tf) | Clones a template; uploads cloud-init vendor-data snippet `<vm>-vendor-data.yaml` that installs and starts `qemu-guest-agent` |
| [`terraform/proxmox/terraform.tfvars.example`](../../terraform/proxmox/terraform.tfvars.example) | Shape of the gitignored `terraform.tfvars` |

#### Templates

| VMID | Template | Cloud image |
|---|---|---|
| 106 | `ubuntu-2404-cloudimg` | Ubuntu 24.04 (noble) |
| 9001 | `debian-13-cloudimg` | Debian 13 (trixie) |
| 9002 | `almalinux-10-cloudimg` | AlmaLinux 10 (disk 10 GB) |

#### VMs

| VMID | Name | Template | Cores / RAM / disk | Address |
|---|---|---|---|---|
| 107 | yarr | Ubuntu | 4 / 32768 MB / 96 GB | DHCP |
| 301 | freeipa | AlmaLinux | 2 / 4096 MB / 32 GB | 10.0.0.31/24 |
| 302 | authentik | Debian | 2 / 6144 MB / 32 GB | 10.0.0.32/24 |
| 303 | vaultwarden | Debian | 1 / 2048 MB / 16 GB | 10.0.0.33/24 |
| 304 | caddy | Debian | 1 / 2048 MB / 16 GB | 10.0.0.34/24 |
| 900 | labtest | Debian | 2 / 2048 MB / 16 GB | DHCP; only when `labtest_enabled` |

Identity VMs use gateway 10.0.0.1, domain `example.com` and DNS server `var.dns_server` (10.0.0.225, [bind9.md](bind9.md)).

### VMID scheme

| Range   | Use                                                                                  |
|---------|--------------------------------------------------------------------------------------|
| 100-199 | Existing/manual VMs. Keep IDs; 106 (Ubuntu template) and 107 (yarr) are Terraform-managed |
| 200-299 | Agent sandboxes                                                                      |
| 301-306 | Core infra: 301 FreeIPA, 302 Authentik, 303 Vaultwarden, 304 Caddy, 305 OPNsense, 306 OpenBao |
| 900-999 | Test/scratch (900 = `labtest`)                                                       |
| 9000+   | New templates (9001 = Debian 13)                                                     |

VM 110 (Jenkins) is managed by a different Terraform config. Never define or import it here.

### Variables

| Variable | Defined in | Value / meaning |
|---|---|---|
| `proxmox_endpoint` | `variables.tf` | default `https://10.0.0.60:8006/api2/json` |
| `proxmox_node_name` | `variables.tf` | default `pve1` |
| `proxmox_insecure_tls` | `variables.tf` | default `true` (skip TLS verification) |
| `proxmox_ssh_username`, `proxmox_ssh_private_key` | `variables.tf` | default `root`, `~/.ssh/id_ed25519`; used by the provider for disk import |
| `template_datastore_id`, `snippet_datastore_id` | `variables.tf` | default `local` |
| `vm_datastore_id` | `variables.tf` | default `local-lvm` |
| `network_bridge`, `vlan_id` | `variables.tf` | default `vmbr0`, `0` (no tag) |
| `admin_user` | `variables.tf` | default `labadmin`; initial cloud-init user |
| `ssh_public_keys` | `variables.tf` | keys injected into new VMs via cloud-init |
| `labtest_enabled` | `variables.tf` | default `false`; creates VM 900 |
| `dns_server` | `variables.tf` | default `10.0.0.225`; RFC 2136 target and VM DNS |
| `dns_zone` | `variables.tf` | default `example.com.` |
| `dns_tsig_key_algorithm` | `terraform.tfvars` | e.g. `hmac-sha256` |

### Secrets

Terraform secrets are in the gitignored `terraform/proxmox/terraform.tfvars` (not Ansible Vault).

| Variable | File | Used for |
|---|---|---|
| `proxmox_api_token_id`, `proxmox_api_token_secret` | `terraform.tfvars` | Proxmox API token (`root@pam!terraform`) |
| `dns_tsig_key_secret` | `terraform.tfvars` | TSIG secret for [bind9.md](bind9.md) dynamic updates |
| `proxmox_oidc_client_secret` | `terraform.tfvars` | OIDC client secret for the Authentik realm |

The Proxmox OIDC client secret for `sso.tf` is `proxmox_oidc_client_secret` in `terraform.tfvars` and must equal `vault_authentik_proxmox_client_secret` (identity vault, see [authentik.md](authentik.md)).

## How it works

`modules/proxmox-template` downloads a cloud image (never re-downloaded once present) and builds a template VM with the guest agent enabled. `modules/proxmox-vm` full-clones a template, sets CPU, memory, disk and cloud-init network/user, and attaches a vendor-data snippet that installs and starts `qemu-guest-agent` on first boot. The `clone` argument is ignored after creation so imported VMs are not replaced.

`sso.tf` creates the Proxmox OpenID realm `authentik` (issuer `https://auth.example.com/application/o/proxmox/`, client id `proxmox`, username claim `username`, scopes `email profile`, `autocreate = false`). Because accounts are not auto-created, the user `labuser@authentik` is declared explicitly and given the `Administrator` role on `/` with propagation.

## Operations

Deploy:

```bash
terraform -chdir=terraform/proxmox init
terraform -chdir=terraform/proxmox plan
terraform -chdir=terraform/proxmox apply
```

### State policy

Terraform state is local: `terraform/proxmox/terraform.tfstate`, gitignored. Back it up after every apply. `terraform.tfvars` and `ansible/.vault_pass` are gitignored and hold credentials.

### Stage 1 rebuild proof

Create labtest from the Debian template, configure, destroy:

```bash
terraform -chdir=terraform/proxmox apply -var labtest_enabled=true
IP=$(terraform -chdir=terraform/proxmox output -raw labtest_ipv4)
(cd ansible && ansible-playbook playbooks/baseline.yml -l labtest -e ansible_host=$IP)
terraform -chdir=terraform/proxmox apply -var labtest_enabled=true -replace='module.labtest_vm[0].proxmox_virtual_environment_vm.vm'
terraform -chdir=terraform/proxmox apply     # labtest_enabled=false destroys it
```

`baseline.yml` is described in [host-baseline.md](host-baseline.md).

Known gaps:

- The Proxmox API token was previously committed in the yarr repo; rotate it and update only `terraform/proxmox/terraform.tfvars`.
