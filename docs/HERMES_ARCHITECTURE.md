# Hermes WebUI + FreeLLMAPI Architecture

**Date:** 2026-10-17
**Status:** Redeployed and operational at https://hermes.fx504.duckdns.org

---

## Overview

Hermes WebUI is a chat interface for AI agents that connects to LLM backends via OpenAI-compatible API endpoints. On fx504, it uses **FreeLLMAPI** as its model gateway, which routes requests to various upstream providers (Claude, GPT, etc.) through a unified interface.

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT LAYER                            │
│                                                                 │
│   Browser → https://hermes.fx504.duckdns.org                   │
│              https://home.fx504.duckdns.org (dashboard)         │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CADDY REVERSE PROXY                     │
│                                                                 │
│   @hermes → 127.0.0.1:8787                                     │
│   TLS: *.fx504.duckdns.org (wildcard, DNS-01 challenge)        │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      HERMES WEBUI (port 8787)                   │
│                                                                 │
│   · Chat backend: gateway mode                                  │
│   · State: ~/.hermes/webui/                                     │
│   · Sessions, memories, skills, SOUL.md                        │
│   · Workspace mount: /home/jguy/Workspace                       │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FREE LLMAPI (port 3001)                    │
│                                                                 │
│   · OpenAI-compatible endpoint                                  │
│   · Model routing / fallback chain                              │
│   · Rate limiting, caching, compression                         │
│   · API key management                                          │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      UPSTREAM PROVIDERS                         │
│                                                                 │
│   · Claude (Anthropic)                                          │
│   · OpenAI (GPT models)                                         │
│   · Grok / xAI                                                  │
│   · DeepSeek                                                    │
│   · Ollama (local models, optional)                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Network Topology

### Docker Networking

Hermes WebUI runs in its own Docker Compose stack but connects to the freellmapi network:

```yaml
networks:
  freellmapi_net:
    external: true
    name: freellmapi_default
```

This allows Hermes to reach freellmapi by container name (`http://freellmapi:3001`) rather than host loopback, which is required because freellmapi publishes on `127.0.0.1:8082` (host-only).

### Port Binding

| Service | Host Binding | Purpose |
|---------|--------------|---------|
| Hermes WebUI | `127.0.0.1:8787` | LAN-hardened; only Caddy can reach it |
| FreeLLMAPI | `127.0.0.1:8082` | LAN-hardened; only Caddy can reach it |

Both services are isolated from direct external access. All traffic flows through Caddy's reverse proxy.

### Caddy Route

```caddyfile
@hermes host hermes.fx504.duckdns.org
handle @hermes {
    reverse_proxy 127.0.0.1:8787
}
```

The `@hermes` matcher is placed **inside the existing wildcard site block** to avoid triggering a separate DuckDNS DNS-01 challenge (which would reset the A record to the public IP).

---

## Security Design

### Hardening Measures

1. **Loopback-only binding** — Hermes is not directly accessible via the LAN IP or Tailscale. Only Caddy can route to it.
2. **Password protection** — `HERMES_WEBUI_PASSWORD` is required; access is restricted.
3. **Gateway mode** — Hermes does not directly call upstream providers; all traffic routes through FreeLLMAPI for centralized control.
4. **No `depends_on`** — Hermes depends on freellmapi being healthy, but they are in separate Docker Compose projects. Startup order is managed by Docker's restart policy (`unless-stopped`).

### Secrets Management

| Secret | Source | Location |
|--------|--------|----------|
| DuckDNS API Token | Caddy `.env` | `/var/mnt/storage/docker/stacks/caddy/.env` |
| Hermes WebUI Password | Generated at deploy | `/var/mnt/storage/docker/stacks/hermes-webui/.env` |
| FreeLLMAPI Encryption Key | Existing deployment | `/var/mnt/storage/docker/stacks/freellmapi/.env` |

All secrets live in `.env` files and are excluded from git via `.gitignore`.

---

## Deployment Details

### Stack Location

```
/var/mnt/storage/docker/stacks/hermes-webui/
├── compose.yaml
├── .env
├── .env.example
└── data/ (volume: /var/mnt/storage/hermes-data)
```

### Docker Compose Configuration

```yaml
services:
  hermes-webui:
    image: ghcr.io/nesquena/hermes-webui:latest
    container_name: hermes-webui
    restart: unless-stopped
    ports:
      - "127.0.0.1:8787:8787"
    volumes:
      - ${HERMES_HOME:-/var/mnt/storage/hermes-data}:/home/hermeswebui/.hermes
      - ${HERMES_WORKSPACE:-/home/jguy/Workspace}:/workspace
    environment:
      - WANTED_UID=${UID:-1000}
      - WANTED_GID=${GID:-1000}
      - HERMES_WEBUI_HOST=0.0.0.0
      - HERMES_WEBUI_PORT=8787
      - HERMES_WEBUI_STATE_DIR=/home/hermeswebui/.hermes/webui
      - HERMES_WEBUI_PASSWORD=${HERMES_WEBUI_PASSWORD}
      - HERMES_WEBUI_CHAT_BACKEND=gateway
      - HERMES_WEBUI_GATEWAY_BASE_URL=${HERMES_WEBUI_GATEWAY_BASE_URL}
      - HERMES_WEBUI_GATEWAY_API_KEY=${HERMES_WEBUI_GATEWAY_API_KEY:-}
    networks:
      - freellmapi_net
```

### Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `HERMES_WEBUI_PASSWORD` | `<generated>` | WebUI login password |
| `HERMES_WEBUI_GATEWAY_BASE_URL` | `http://freellmapi:3001` | Gateway endpoint (container name) |
| `HERMES_WEBUI_GATEWAY_API_KEY` | (empty) | Not required by current freellmapi config |
| `HERMES_HOME` | `/var/mnt/storage/hermes-data` | Persistent state directory |
| `HERMES_WORKSPACE` | `/home/jguy/Workspace` | Shared workspace for agent file access |

---

## History & Lessons Learned

### Why Hermes Was Previously Removed (2026-08-30)

The first Hermes deployment failed because:
1. It used a free-tier model that couldn't reliably use its own tools
2. It reported false successes (e.g., claimed to create Notion rows it didn't create)
3. Maintenance burden was high relative to utility

### Why Hermes Was Redeployed (2026-10-17)

The user requested redeployment with the following improvements:
1. **Gateway mode** — Hermes now routes through FreeLLMAPI instead of direct provider calls
2. **Better model selection** — FreeLLMAPI can route to Claude/GPT for reliable tool use
3. **Persistent state** — Data volume mounted for sessions, memories, and skills
4. **Workspace integration** — `/home/jguy/Workspace` mounted for file operations

### Critical Constraint: DuckDNS A Record Clobbering

**Problem:** When Hermes was redeployed, the Caddy configuration had to be carefully managed to avoid triggering a separate DNS-01 challenge.

**Root Cause:** If Hermes's Caddy route were placed in a separate top-level site block (`hermes.fx504.duckdns.org { ... }`), Caddy would attempt to obtain a new certificate for the bare domain. The DNS-01 challenge calls the DuckDNS `/update` API, which resets the A record to the caller's public IP — breaking all homelab services.

**Solution:** The `@hermes` matcher was added **inside the existing wildcard site block** (`fx504.duckdns.org, *.fx504.duckdns.org { ... }`), reusing the existing wildcard certificate and avoiding any new certificate requests.

**Documentation:** This incident is recorded in `docs/INCIDENTS.md`.

---

## Verification

After deployment, verify:

```bash
# Container running
docker ps | grep hermes-webui

# Network path to gateway
docker exec hermes-webui curl -s -o /dev/null -w '%{http_code}\n' http://freellmapi:3001/

# Through Caddy (with SNI workaround)
curl -sk -o /dev/null -w '%{http_code}\n' \
  --resolve hermes.fx504.duckdns.org:443:192.168.4.38 \
  https://hermes.fx504.duckdns.org/

# A record safety check
dig +short @ns1.duckdns.org fx504.duckdns.org A
# Expected: 192.168.4.38
```

---

## Related Documentation

- `docs/INCIDENTS.md` — DuckDNS A record clobbering incident
- `docs/ARCHITECTURE.md` — Overall homelab architecture
- `docs/STATE.md` — Current service status
