# AI Home Lab — Deployment Plan

Target architecture for the lab. Goals:

- Keep core infrastructure **stable**.
- Keep Kubernetes **lightweight**.
- Keep AI agents **isolated**.

Implementation lives in this repo; see [README.md](README.md) for what is deployed today and [docs/bootstrap.md](docs/bootstrap.md) for first-time setup.

## Contents

1. [Endpoint assignments](#1-endpoint-assignments)
2. [Proxmox: core infrastructure](#2-proxmox-core-infrastructure)
3. [Raspberry Pi K3s cluster](#3-raspberry-pi-k3s-cluster)
4. [NAS: storage and backups](#4-nas-storage-and-backups)
5. [GPU inference](#5-gpu-inference)
6. [Networking and remote access](#6-networking-and-remote-access)
7. [Agent isolation and security](#7-agent-isolation-and-security)
8. [Deployment order](#8-deployment-order)
9. [Risks and failure modes](#9-risks-and-failure-modes)
10. [Open decisions](#10-open-decisions)

## 1. Endpoint assignments

| Endpoint          | Hardware                 | Role                                                  |
| ----------------- | ------------------------ | ----------------------------------------------------- |
| Proxmox           | 8 cores, 64 GB RAM       | Core infrastructure VMs, security services, sandboxes |
| Raspberry Pi 1    | Pi 5, ~4 GB, SD card     | K3s control plane                                     |
| Raspberry Pi 2    | Pi 5, ~4 GB, SD card     | K3s worker                                            |
| Raspberry Pi 3    | Pi 5, ~4 GB, SD card     | K3s worker                                            |
| Raspberry Pi 4    | Pi 5, ~4 GB, SD card     | K3s worker                                            |
| Linux NAS         | ZFS                      | Gitea, storage, backups                               |
| GPU inference box   | 24 GB VRAM               | Fast LLM inference, occasional fine-tuning            |
| Large-memory inference box | Planned, 128 GB          | Large-model inference                                 |
| Tailscale         | Across trusted endpoints | Private remote access                                 |

K3s schedules applications across the Pi cluster, so applications do not need to be pinned to a specific worker.

### Current host names

| Endpoint  | Host name / address                            |
| --------- | ---------------------------------------------- |
| Proxmox   | `pve1`, 10.0.0.60                     |
| Linux NAS | `nas`, 10.0.0.225                         |
| Pis (K3s) | `k3s-1` … `k3s-4`, 10.0.0.41 … 10.0.0.44 |

`k3s-1` is the control plane; `k3s-2` to `k3s-4` are agents.

## 2. Proxmox: core infrastructure

Debian VMs run containerized applications with Docker Compose. Infrastructure configuration is kept in Gitea, and Ansible configures the VMs.

| VM                     | Services              | Starting resources | Deployment     |
| ---------------------- | --------------------- | ------------------ | -------------- |
| VM 301 — Identity      | FreeIPA               | 2 vCPU, 4 GB       | Native install |
| VM 302 — SSO           | Authentik, PostgreSQL | 2 vCPU, 6 GB       | Docker Compose |
| VM 303 — Passwords     | Vaultwarden           | 1 vCPU, 2 GB       | Docker Compose |
| VM 304 — Reverse proxy | Caddy                 | 1 vCPU, 2 GB       | Docker Compose |
| VM 305 — Firewall      | OPNsense              | 2 vCPU, 4 GB       | Dedicated VM   |
| VM 306 — Secrets       | OpenBao (later)       | 2 vCPU, 4 GB       | Dedicated VM   |
| VM 200+ — Agents       | Disposable Ubuntu     | Variable           | Dedicated VMs  |

VMIDs follow the scheme in [README.md](README.md#vmid-scheme).

These are starting allocations, not measured requirements. CPU can be overcommitted through virtualization; watch actual **memory** usage.

Fixed allocations for the VMs above total 8 vCPU / 18 GB for 301-305, plus 2 vCPU / 4 GB once OpenBao is added. That leaves most of the 64 GB for the existing VMs, agent sandboxes, and ZFS/host overhead.

### Identity design

- FreeIPA is authoritative for Linux users, groups, and SSH access.
- Authentik connects to FreeIPA and provides application SSO through OIDC or SAML.
- Vaultwarden stays independently accessible if SSO fails.
- OpenBao eventually manages machine secrets, not personal passwords.
- Independent emergency administrator accounts are retained.

### Deferred

Do not deploy OpenBao or agent sandboxes immediately.

## 3. Raspberry Pi K3s cluster

Start with one control-plane node and three workers, because the nodes currently boot from SD cards.

| Application         | Purpose                                   | Priority |
| ------------------- | ----------------------------------------- | -------- |
| Flux CD             | GitOps deployments from Gitea             | First    |
| SOPS + age          | Encrypted Kubernetes secrets in Git       | First    |
| LiteLLM             | Unified API gateway for both GPU machines | First    |
| Lightweight metrics | Cluster and application monitoring        | Early    |
| Grafana             | Dashboards                                | Later    |
| LangGraph service   | Coding and research agent orchestration   | Later    |

Guidelines:

- Use supported ARM64 container images.
- Keep persistent writes modest to protect the SD cards.
- Back up the K3s datastore.
- Plan an eventual SSD upgrade.
- Three control-plane nodes with embedded etcd can come later.

> **Important:** agent orchestration can run on K3s, but untrusted code execution belongs in disposable Proxmox VMs.

## 4. NAS: storage and backups

The NAS (`nas`) hosts Gitea, bulk storage, and backups. It is the first thing to build, because every later stage depends on being able to restore.

| Data                             | Source      | Destination | Notes                                         |
| -------------------------------- | ----------- | ----------- | --------------------------------------------- |
| Gitea repositories and database  | NAS         | ZFS dataset | Snapshot, then replicate off the NAS          |
| Proxmox VM backups               | Proxmox     | NAS share   | Scheduled `vzdump`                            |
| K3s datastore                    | `k3s-1`     | NAS share   | Encrypted with age; see the `k3s_backup` role |
| Terraform state                  | Workstation | NAS         | State is local; copy after every apply        |
| Ansible vault password, age keys | Workstation | Vaultwarden | Never only in Git or only on one machine      |

Guidelines:

- Use ZFS snapshots for fast local rollback; they are not a backup on their own.
- Keep at least one copy off the NAS (second disk or offsite).
- Test a restore, not just a backup job, before relying on it.

## 5. GPU inference

| Machine                      | Role                                                               | Exposed through |
| ---------------------------- | ------------------------------------------------------------------ | --------------- |
| GPU box (24 GB)          | Fast inference for small and medium models, occasional fine-tuning | LiteLLM         |
| Large-memory box (128 GB, planned) | Large models where capacity matters more than speed                | LiteLLM         |

- Each machine runs its own inference server and exposes an OpenAI-compatible API on the LAN or Tailscale only.
- LiteLLM on K3s is the single entry point. Clients and agents use one URL and one key and never talk to a GPU box directly.
- Route by model name: small and fast models go to the GPU box, large models go to the large-memory box.
- Issue a separate LiteLLM key per agent or service so usage can be limited and revoked individually.
- Fine-tuning jobs are scheduled manually so they do not starve interactive inference on the GPU box.

## 6. Networking and remote access

- **Tailscale** provides private remote access across trusted endpoints. Use hosted coordination initially (see [Open decisions](#10-open-decisions)).
- **Caddy** (VM 304) is the single HTTPS entry point for web services, with Authentik forward auth where an application has no SSO of its own.
- **OPNsense** (VM 305) enforces segmentation between trusted infrastructure and agent sandboxes. It arrives in stage 5.
- Internal DNS for `example.com` is served from the NAS; Terraform writes records to it.

Do not expose Proxmox, FreeIPA, or any GPU API directly to the internet.

## 7. Agent isolation and security

Agents are treated as untrusted code runners with limited, explicit access.

| Layer       | Control                                                                       |
| ----------- | ----------------------------------------------------------------------------- |
| Execution   | Disposable Proxmox VMs (200+), cloned from a template and destroyed after use |
| Network     | Dedicated segment behind OPNsense; default deny to the rest of the LAN        |
| Allow-list  | LiteLLM, Gitea, and any package mirrors an agent needs                        |
| Credentials | Short-lived and scoped to one agent; never personal passwords or admin tokens |
| Secrets     | OpenBao for machine secrets once deployed                                     |

Agents must **not** reach: Proxmox management, FreeIPA, Vaultwarden, OpenBao, the NAS backup shares, or the K3s control plane.

## 8. Deployment order

Implement in five stages.

| Stage                   | Deploy                                                    | Completion check                                                 |
| ----------------------- | --------------------------------------------------------- | ---------------------------------------------------------------- |
| 1 — Foundation          | NAS backups, Gitea repositories, VM templates, Ansible    | A test VM can be rebuilt from configuration                      |
| 2 — Identity            | Caddy, FreeIPA, Authentik, Vaultwarden                    | HTTPS, SSO, MFA, and recovery accounts work                      |
| 3 — Kubernetes          | K3s, Flux CD, SOPS, lightweight monitoring                | A Git commit deploys a test application                          |
| 4 — Inference           | GPU inference APIs, LiteLLM                               | One private API reaches both inference endpoints                 |
| 5 — Agents and security | OPNsense, isolated agent VMs, LangGraph, optional OpenBao | Agents perform approved tasks without reaching protected systems |

Before relying on centralized authentication, verify that you can still log into Proxmox and recover Vaultwarden while Authentik or FreeIPA is unavailable.

### Recommended first deployment

1. NAS backups and Proxmox VM templates.
2. Caddy, FreeIPA, Authentik, and Vaultwarden.
3. The Pi cluster, with Flux CD connected to Gitea.

This establishes a stable foundation before introducing autonomous agents.

## 9. Risks and failure modes

| Risk                               | Impact                                             | Mitigation                                                          |
| ---------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------- |
| Pi SD card wear or failure         | Cluster nodes or K3s datastore lost                | Modest writes, K3s datastore backups, eventual SSD upgrade          |
| FreeIPA or Authentik outage        | Locked out of SSO-protected services               | Local break-glass admins; Vaultwarden and Proxmox have local logins |
| Single NAS holds Gitea and backups | Gitea outage stalls GitOps; NAS loss loses backups | Off-NAS backup copy; keep bootstrap steps documented                |
| Agent escapes its sandbox          | Access to lab systems                              | VM isolation, OPNsense segmentation, scoped credentials             |
| ~4 GB Pis run out of memory        | Evicted pods, unstable nodes                       | Resource requests and limits; keep heavy services off K3s           |
| Resource sizing is a guess         | Over- or under-provisioned VMs                     | Measure memory after deployment and adjust                          |

## 10. Open decisions
