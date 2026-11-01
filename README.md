# homelab

Single infrastructure-as-code repo for the lab described in [labplan.md](labplan.md). Terraform builds Proxmox templates and VMs; Ansible configures them.

Current scope: Stage 1 "Foundation" (templates, Ansible, rebuildable test VM), Stage 2 "Identity" (FreeIPA, Authentik, Vaultwarden, Caddy) with SSO in front of the yarr media stack and Gitea, and Stage 3 "Kubernetes" (K3s on four Raspberry Pis, Flux CD from Gitea, SOPS, MetalLB and Traefik ingress, VictoriaMetrics, Gitea Actions runners). Migrated from the former `yarr` repo.

## What runs where

![Homelab overview](docs/img/lab-overview.svg)

| Service | Host | Notes | Doc |
|---------|------|-------|-----|
| FreeIPA | VM 301, 10.0.0.31 | Users, groups, sudo/HBAC. Admin group `lab-admins` | [freeipa.md](docs/services/freeipa.md) |
| Authentik | VM 302, 10.0.0.32 | SSO (`auth.example.com`); FreeIPA is its LDAP source; MFA (TOTP) for everyone | [authentik.md](docs/services/authentik.md) |
| Vaultwarden | VM 303, 10.0.0.33 | `vault.example.com`; Authentik SSO as an extra login | [vaultwarden.md](docs/services/vaultwarden.md) |
| Caddy | VM 304, 10.0.0.34 | Reverse proxy, Let's Encrypt (GoDaddy DNS-01); Authentik forward auth | [caddy.md](docs/services/caddy.md) |
| yarr stack | VM 107, 10.0.0.160 | Plex, Sonarr, Radarr, Prowlarr, qBittorrent (behind Gluetun), FlareSolverr, Homarr, Watchtower | [yarr-stack.md](docs/services/yarr-stack.md) |
| Gitea | nas, 10.0.0.225 | `gitea.example.com`; Authentik OIDC login | [gitea.md](docs/services/gitea.md) |
| Uptime Kuma | nas, 10.0.0.225:3001 | Up/down checks for every lab service; `uptime.example.com` | [uptime-kuma.md](docs/services/uptime-kuma.md) |
| bind9 | nas, 10.0.0.225 | Authoritative DNS for `example.com` (Terraform writes records via RFC 2136) | [bind9.md](docs/services/bind9.md) |
| Proxmox | pve1, 10.0.0.60 | Authentik OIDC realm (`sso.tf`) | [proxmox.md](docs/services/proxmox.md) |
| K3s cluster | Pis `k3s-1` to `k3s-4`, 10.0.0.41-44 | One server, three agents. Flux CD syncs the Gitea repo `labadmin/k3s-fleet`. Ingress at `*.k3s.example.com` (10.0.0.50). VictoriaMetrics, podinfo test app | [k3s.md](docs/k3s.md) |
| Gitea Actions runners | K3s | `ubuntu-latest` (Docker-in-Docker pods) and `k3s-arm64` (one pod per job) | [k3s.md](docs/k3s.md) |

SSO coverage per app: [docs/services/authentik.md](docs/services/authentik.md#sso-coverage).

## Layout

```
terraform/
  modules/proxmox-template/   cloud-image download + template VM
  modules/proxmox-vm/         cloned VM + cloud-init vendor-data snippet
  proxmox/                    root module (local state, gitignored)
    main.tf identity.tf       templates, yarr VM, labtest, identity VMs (301-304)
    dns.tf                    bind9 records: identity hosts, service names (auth, vault, gitea, uptime, sonarr, ...), k3s nodes, *.k3s wildcard
    sso.tf                    Proxmox OIDC realm against Authentik
ansible/
  ansible.cfg  collections/requirements.yml
  inventory/hosts.yml
  inventory/group_vars/{all,yarr,identity,gitea_servers,uptime_kuma_servers,authentik_servers,caddy_servers,vaultwarden_servers,pis,k3s_cluster}/
  inventory/host_vars/
  playbooks/{site,baseline,yarr,identity,gitea,uptime_kuma,ipa_clients,dns,pis,k3s}.yml
  roles/
    common docker nfs_mount                  baseline
    freeipa_server freeipa_client            identity source of truth
    authentik                                SSO + blueprints (homelab, yarr, gitea, opnsense)
    vaultwarden caddy                        passwords, reverse proxy
    internal_dns                             route example.com to the lab DNS server (yarr, nas)
    yarr_stack gitea uptime_kuma             media stack, Gitea (+ their SSO wiring), Uptime Kuma + AutoKuma
    bind9                                    DNS on nas
    k3s backup flux                          K3s on the Pis, datastore backup, Flux bootstrap
scripts/
  ipa-enroll.sh               enroll hosts in FreeIPA
  vault-add-secret.sh         add a random secret to an ansible-vault file
docs/services/               one doc per service: purpose, configuration, how it works, operations
docs/bootstrap.md            first-time whole-lab bootstrap
docs/k3s.md                  K3s, Flux, ingress, runners, backups (with diagrams)
docs/img/                    SVG diagrams used by the docs
```

`group_vars`/`host_vars` live under `ansible/inventory/` so every playbook loads them without `vars_files`.

## Day-2 commands

```bash
# Terraform
terraform -chdir=terraform/proxmox init
terraform -chdir=terraform/proxmox plan
terraform -chdir=terraform/proxmox apply

# Ansible (from ansible/)
cd ansible
ansible-galaxy collection install -r collections/requirements.yml
ansible-inventory --graph
ansible-playbook playbooks/yarr.yml

# Identity, yarr and Gitea (full SSO rebuild order: docs/services/authentik.md)
ansible-playbook playbooks/identity.yml     # FreeIPA, Authentik, Vaultwarden, Caddy
ansible-playbook playbooks/yarr.yml
ansible-playbook playbooks/gitea.yml
ansible-playbook playbooks/uptime_kuma.yml  # Kuma admin + AutoKuma monitors; run after yarr.yml pushes start reporting

# K3s cluster (details: docs/k3s.md)
ansible-playbook playbooks/pis.yml          # Pis: sudo rule, NFS mount, upgrades
ansible-playbook playbooks/k3s.yml          # static IP, K3s, backup timer, kubeconfig, Flux bootstrap
export PATH=~/.local/bin:$PATH; kubectl get nodes -o wide; flux get kustomizations
```

## Known gaps

- The Pis are managed from this workstation (`pis.yml`, `k3s.yml`). K3s runs a single server on an SD card; see "Known gaps" in docs/k3s.md.
- Legacy history (Google LDAP key, sssd config) remains in git history; revoke the key upstream if still valid.
