FROM caddy:2-builder AS builder
# GoDaddy personal access tokens authenticate with "Authorization: Bearer";
# libdns/godaddy hardcodes the legacy "sso-key" scheme, so patch it.
RUN git clone --depth 1 --branch v1.1.0 https://github.com/libdns/godaddy /src/libdns-godaddy \
 && sed -i 's/"sso-key "+p.APIToken/"Bearer "+p.APIToken/g' /src/libdns-godaddy/provider.go \
 && ! grep -q 'sso-key' /src/libdns-godaddy/provider.go
RUN xcaddy build \
    --with github.com/caddy-dns/godaddy \
    --replace github.com/libdns/godaddy=/src/libdns-godaddy

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
