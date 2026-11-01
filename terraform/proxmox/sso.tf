resource "proxmox_realm_openid" "authentik" {
  realm          = "authentik"
  issuer_url     = "https://auth.example.com/application/o/proxmox/"
  client_id      = "proxmox"
  client_key     = var.proxmox_oidc_client_secret
  username_claim = "username"
  scopes         = "email profile"
  autocreate     = false
  comment        = "Authentik SSO"
}

resource "proxmox_virtual_environment_user" "sso_admin" {
  user_id    = "labuser@authentik"
  comment    = "FreeIPA user via Authentik SSO"
  depends_on = [proxmox_realm_openid.authentik]
}

resource "proxmox_acl" "sso_admin" {
  path      = "/"
  role_id   = "Administrator"
  user_id   = proxmox_virtual_environment_user.sso_admin.user_id
  propagate = true
}
