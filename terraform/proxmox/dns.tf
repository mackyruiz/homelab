resource "dns_a_record_set" "identity_host" {
  for_each = local.identity_vms

  zone      = var.dns_zone
  name      = each.key
  addresses = [each.value.ip]
  ttl       = 300
}

resource "dns_a_record_set" "service" {
  for_each = {
    auth        = local.identity_vms.caddy.ip
    vault       = local.identity_vms.caddy.ip
    sonarr      = local.identity_vms.caddy.ip
    radarr      = local.identity_vms.caddy.ip
    prowlarr    = local.identity_vms.caddy.ip
    qbittorrent = local.identity_vms.caddy.ip
    gitea       = local.identity_vms.caddy.ip
    homarr      = local.identity_vms.caddy.ip
    "ipa-ca"    = local.identity_vms.freeipa.ip
  }

  zone      = var.dns_zone
  name      = each.key
  addresses = [each.value]
  ttl       = 300
}

resource "dns_srv_record_set" "freeipa" {
  for_each = {
    "_ldap._tcp"            = 389
    "_kerberos._tcp"        = 88
    "_kerberos._udp"        = 88
    "_kerberos-master._tcp" = 88
    "_kerberos-master._udp" = 88
    "_kpasswd._tcp"         = 464
    "_kpasswd._udp"         = 464
  }

  zone = var.dns_zone
  name = each.key
  ttl  = 300

  srv {
    priority = 0
    weight   = 100
    port     = each.value
    target   = "freeipa.example.com."
  }
}

resource "dns_txt_record_set" "kerberos_realm" {
  zone = var.dns_zone
  name = "_kerberos"
  txt  = ["EXAMPLE.COM"]
  ttl  = 300
}
