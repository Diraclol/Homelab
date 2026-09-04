# Architecture

<!-- diagram: docs/img/architecture.svg (Excalidraw export) — add in a follow-up commit -->

## Host

| | |
|---|---|
| Hardware | Asus TUF FX504GD laptop · i5-8300H · 24 GB RAM · GTX 1050 2 GB |
| OS | Bazzite (immutable Fedora, rpm-ostree) |
| Storage | 1 TB SATA for data · 236 GB NVMe for OS |
| Containers | Docker Compose, one directory per stack |

An immutable OS means the base system is a read-only image: a bad update is rolled back with
one command and the host cannot drift. All state lives in Compose volumes on the data disk.

## Name resolution and TLS

- A DuckDNS domain resolves to the host's **private** LAN address. Off-LAN, the name resolves
  to something unreachable — which is the point.
- Caddy holds a wildcard Let's Encrypt certificate obtained via the **DNS-01** challenge using
  the DuckDNS API. DNS-01 proves domain control by writing a TXT record, so no inbound HTTP is
  required and the host is never reachable from the internet.
- Every service gets its own hostname and Caddy proxies it to the container port. No port
  numbers in URLs; the bare domain redirects to the dashboard.

## Remote access

Tailscale (WireGuard) with a `/32` subnet route advertising **only this host**, not the home
network. Clients that use the tailnet's DNS resolve the same hostnames to the same private
address, over the same certificate. Rejected alternatives in [DECISIONS.md](DECISIONS.md).

## Streaming

Sunshine captures the laptop display (mirrored to the TV); Moonlight Web serves a browser
client so a guest can drive the TV with no app install. Runs with `network_mode: host` because
WebRTC ICE needs the real interface.

Guest access is a role-restricted account that cannot add hosts or change settings, with browser
auto-login so a roommate opens one URL and is on the TV. It is reachable only on the LAN and the
tailnet, and it is explicitly excluded from any future public tunnel: that path gets its own
authentication design before anything is exposed.

## What is deliberately not here

- No AI agent on the host. Tried, measured, removed — a scheduled report does not need a model.
- No public exposure. Anything that ever needs to be public goes through a tunnel with its own
  auth design first.
- No VLANs yet — the router isn't mine. The firewall inventory is the interim control.
