# caddy

Custom Caddy image built with `xcaddy` and the DuckDNS DNS provider module, so the wildcard
certificate is obtained via DNS-01 with no inbound port 80.

Files to add here from the host: `compose.yaml`, `Dockerfile`, `Caddyfile`.
`build_repo.sh` copies and scrubs this file for you; check REVIEW.md afterwards.
