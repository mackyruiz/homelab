# OPNsense WebGUI SSO

Login to the router's WebGUI through [Authentik](authentik.md), using the third-party os-sso plugin; the router itself is not managed by this repo.

| | |
|---|---|
| Host | OPNsense router, 10.0.0.1 (not managed by this repo) |
| Address / URL | `https://10.0.0.1` (`opnsense_gui_url`) |
| Ports | WebGUI on 443 (`opnsense_gui_url` has no port; include one if the GUI moves) |
| Software | OPNsense >= 25.7 with the os-sso plugin, pinned `v2026.10.3` (`os-sso-devel-2026.10.3-FreeBSD-N.pkg`) |
| Data | os-sso configuration in `/conf/config.xml` on the router |
| Deployed by | Authentik side: `playbooks/identity.yml` (role `authentik`, blueprint `opnsense.yaml.j2`). Router side: manual |
| Depends on | [Authentik](authentik.md) (OIDC provider, client `opnsense`), [Caddy](caddy.md) (the router's `auth` host override points at Caddy, 10.0.0.34), [FreeIPA](freeipa.md) (the `lab-admins` group) |
| Used by | Nothing in the repo; administrators log in to the router with it |

## Purpose

The Authentik side (`blueprints/opnsense.yaml.j2`, client `opnsense`, only `lab-admins`) is applied by `identity.yml`. The router is not managed by this repo, so the OPNsense side is manual. It uses the third-party plugin [os-sso](https://github.com/MaximeWewer/os-sso) (OPNsense >= 25.7). Community Edition has no built-in OIDC.

## Configuration

### Files

| Path | What it sets |
|------|--------------|
| [`ansible/roles/authentik/templates/blueprints/opnsense.yaml.j2`](../../ansible/roles/authentik/templates/blueprints/opnsense.yaml.j2) | OIDC provider `OPNsense` (client `opnsense`), application `opnsense`, expression policy "OPNsense: lab-admins only" and its binding |
| [`ansible/inventory/group_vars/all/main.yml`](../../ansible/inventory/group_vars/all/main.yml) | `opnsense_gui_url`, `sso_admin_group` |
| [`ansible/roles/authentik/templates/env.j2`](../../ansible/roles/authentik/templates/env.j2) | Passes the client secret to Authentik as `AUTHENTIK_OPNSENSE_CLIENT_SECRET` |

### Variables

| Variable | Defined in | Value / meaning |
|----------|------------|-----------------|
| `opnsense_gui_url` | `group_vars/all/main.yml` | `https://10.0.0.1`. Base URL registered at Authentik (redirect URIs `<url>/api/sso/oidc/callback` and `<url>/api/sso/oidc/loggedout`) and in os-sso; include the port if the GUI does not listen on 443 |
| `sso_admin_group` | `group_vars/all/main.yml` | `lab-admins`; the only group the Authentik policy lets through, mapped to `admins` on the router |

### Secrets

| Vault variable | Vault file | Used for |
|----------------|------------|----------|
| `vault_authentik_opnsense_client_secret` | `group_vars/identity/vault.yml` | OIDC client secret for client `opnsense`: rendered into Authentik's `.env` and entered by hand in os-sso (step 3). Add it with `scripts/vault-add-secret.sh` as described in [authentik](authentik.md#rebuilding-sso) |

### Manual steps

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

## How it works

The browser opens the router's WebGUI and clicks the os-sso button "Login with Authentik". os-sso runs an OIDC authorization-code flow with PKCE against the Authentik provider `OPNsense` (issuer `https://auth.example.com/application/o/opnsense/`), and the user signs in with the usual Authentik login and MFA ([authentik](authentik.md)). The group claim `groups` comes from Authentik's stock profile scope, so no custom scope mapping is needed.

The blueprint is shaped around what os-sso accepts:

- **Grant:** `authorization_code` only. os-sso never uses refresh tokens.
- **Signing key:** the asymmetric self-signed certificate (RS256); os-sso refuses symmetric ID-token signatures.
- **Redirect URIs:** `<opnsense_gui_url>/api/sso/oidc/callback`, plus `<opnsense_gui_url>/api/sso/oidc/loggedout` as a logout redirect URI.
- **Access:** an expression policy `OPNsense: lab-admins only` is bound to the application, so only members of `lab-admins` can even reach the firewall. It is a policy rather than a group binding because the FreeIPA group exists only after the first LDAP sync.

On the router, os-sso creates the user automatically, requires the `lab-admins` group, maps it to the OPNsense group `admins`, and deprovisions the user when a login is refused. The router resolves `auth.example.com` through the Unbound host override from step 1, since its resolver otherwise returns NXDOMAIN for internal names.

## Operations

Deploy the Authentik side from `ansible/`: `ansible-playbook playbooks/identity.yml` (or `-l authentik` to limit it). Everything else is the manual steps above. Verify with System > Access > SSO Diagnostics (step 4): **Test** succeeds.

Notes:

- Break-glass is local `root` with its password (the normal login form).
- The os-sso config lives in `/conf/config.xml` and survives firmware upgrades, but after a major OPNsense upgrade the package may need `pkg add` again; the SSO button is missing until then.
- If the GUI port or address changes: update `opnsense_gui_url`, rerun `identity.yml -l authentik`, and update the Base URL.
- If login is refused with a "required groups" message (System > Log Files > General), add a scope mapping `scope_name: groups` with `return {"groups": [g.name for g in request.user.all_groups()]}` to the blueprint, attach it to the provider, and set Scopes to `openid,email,profile,groups`.
