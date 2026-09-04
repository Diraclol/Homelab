# Homelab

Self-hosted services on a single repurposed laptop (Asus TUF FX504, i5-8300H, 24 GB RAM,
GTX 1050) running Bazzite, an immutable Fedora-based OS. Eleven containers across seven
Docker Compose stacks, every service behind HTTPS on a wildcard Let's Encrypt certificate,
reachable from anywhere over Tailscale with nothing exposed to the public internet.

<!-- TODO: add docs/img/architecture.svg and a dashboard screenshot here -->

## What runs

| Stack | Service | Purpose |
|---|---|---|
| `caddy` | Caddy (custom build) + DuckDNS | Reverse proxy, wildcard TLS via DNS-01 |
| `immich` | Immich + Postgres + Redis + ML | Self-hosted photo library (replaces Google Photos) |
| `ai` | Ollama + Open WebUI | Local LLM inference on the GPU |
| `homepage` | Homepage | Service dashboard with live status |
| `dockge` | Dockge | Compose stack management UI |
| `glances` | Glances | Host monitoring |
| `moonlight-web` | Moonlight Web + Sunshine | Browser-based game/desktop streaming to the living-room TV |

## Design in one paragraph

DNS for the whole domain points at a **private** LAN address, so hostnames only resolve on the
LAN or over the tailnet. Caddy terminates TLS for every service using a wildcard certificate
obtained through the DNS-01 challenge (no inbound port 80/443 from the internet is ever needed).
Tailscale advertises a `/32` subnet route for just this host, so the same hostnames and the same
certificate work identically at home and away. There is no port forwarding and no public
exposure. Details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Docs

| File | What it is |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Network, proxy, DNS and remote-access design |
| [docs/INCIDENTS.md](docs/INCIDENTS.md) | Append-only log of every problem: symptom → cause → fix → rule |
| [docs/RECOVERY.md](docs/RECOVERY.md) | Disaster-recovery runbook, tested |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Why things are the way they are |

## Highlights from the incident log

- **Local LLM inference had been running on the CPU for six weeks.** Proved the container could
  not see the GPU, added the NVIDIA container runtime — roughly 10× throughput.
- **A streaming service exited cleanly after every reboot but never bound its port.** Replaced
  process-state checks with a systemd timer that health-checks the listening socket.
- **A pre-built reverse-proxy image could not bind port 443.** Rebuilt Caddy from source with
  `xcaddy` to get the DNS-01 plugin working on a non-root container.

## Secrets

No secret is committed. Every `.env` has a matching `.env.example` with the variable names and
nothing else. The credential manager is the source of truth; `.env` files on the host are
runtime copies. See `.gitignore`.

## Layout

```
stacks/<name>/compose.yaml   one directory per Compose stack
stacks/<name>/.env.example   variable names only
systemd/                     host-level units (battery cap, health-check timers)
docs/                        architecture, incidents, recovery, decisions
```
