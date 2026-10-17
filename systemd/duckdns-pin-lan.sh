#!/usr/bin/env bash
# Pin the DuckDNS A record to this host's current LAN IP.
# Caddy's DNS-01 cert renewals reset it to the PUBLIC IP; this puts it back.
set -euo pipefail
. /var/mnt/storage/docker/stacks/caddy/.env
LAN=$(ip -4 route get 1.1.1.1 | sed -n 's/.*src \([0-9.]*\).*/\1/p')
curl -fsS "https://www.duckdns.org/update?domains=fx504&token=${DUCKDNS_API_TOKEN}&ip=${LAN}" | grep -q OK
