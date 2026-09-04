# fx504 — Tracking

*Last updated: 2026-08-30, late evening*
*Status document. What's running, what's done, what's next. No fix procedures — those live in `fx504-recovery-cribsheet-v9.md`.*

---

## AT A GLANCE

| | |
|---|---|
| **Homelab** | Done and stable. Nothing outstanding. |
| **Remote access** | Done. Works from anywhere via Tailscale. |
| **TV guest streaming** | Done. Browser URL, no install. |
| **Agent / AI layer** | Nothing installed. Deliberate. |

---

## THE MACHINE

| | |
|---|---|
| Host | `fx504` — Asus TUF FX504GD laptop |
| OS | Bazzite (immutable, Fedora-based) |
| Specs | i5-8300H · 24 GB RAM · GTX 1050 2GB |
| Storage | 1 TB SATA at `/var/mnt/storage` · 236 GB NVMe for OS |
| LAN | `192.168.x.x` (wifi) · `192.168.x.x` (ethernet) |
| Tailscale | `100.x.x.x` |
| SSH | `ssh user@192.168.x.x` |
| Stacks | `/var/mnt/storage/docker/stacks/` |

**Other devices:** ThinkPad T14 (`laptop`, Windows) · Pixel 8a

---

## WHAT'S RUNNING

**11 containers across 7 stacks** — `ai`, `caddy`, `dockge`, `glances`, `homepage`, `immich`, `moonlight-web`

| Service | URL | Port |
|---|---|---|
| Homepage | `home.example.duckdns.org` | 3001 |
| Open WebUI | `webui.example.duckdns.org` | 3000 |
| Immich | `photos.example.duckdns.org` | 2283 |
| Dockge | `dockge.example.duckdns.org` | 5001 |
| Glances | `glances.example.duckdns.org` | 61208 |
| Cockpit | `cockpit.example.duckdns.org` | 9090 |
| Sunshine (web UI) | `stream.example.duckdns.org` | 47990 |
| Moonlight Web | `tv.example.duckdns.org` | 8080 |
| Ollama | — | 11434 |

All HTTPS, real Let's Encrypt wildcard cert, **no port numbers in URLs**. Bare `example.duckdns.org` redirects to home.

**Nothing is exposed to the internet.** No port forwarding. DuckDNS points at a private IP.

---

## REMOTE ACCESS — how it works

Same URLs everywhere, home or away.

- **At home:** DNS resolves `192.168.x.x`, direct LAN route.
- **Away:** Tailscale on → subnet route `192.168.x.x/32` carries it. Same name, same cert.
- **Tailscale off, away:** nothing resolves. Expected.

Immich mobile app endpoint: `https://photos.example.duckdns.org`

---

## TV GUEST ACCESS — how it works

A roommate opens **`https://tv.example.duckdns.org`**, lands straight in, clicks the host, launches
Desktop, and is driving the TV. No app install, no account, no password.

| | |
|---|---|
| Stack | `/var/mnt/storage/docker/stacks/moonlight-web/` |
| Image | `mrcreativ3001/moonlight-web-stream:v2.10.0` (pinned) |
| Network | `network_mode: host` — required, fixes ICE candidates and Sunshine localhost access |
| Accounts | `admin` (full rights) · `guest` (Guest role, cannot add hosts) |
| Guest access | Browser auto-login into the restricted guest role. The exact account and cookie settings are not settable from the UI and live in private notes; if the stack is rebuilt they must be re-applied or the guest gets a login box. |

**Known limits:**
- **One client at a time.** A guest connecting kicks whoever is streaming, including you.
- **No clipboard sync** between the guest's laptop and the fx504 — GameStream has no clipboard
  channel. Copy/paste *inside* the remote desktop works fine via Send Keycode.
- Sunshine captures `eDP-1`, the laptop panel. Fine while the TV mirrors it.

---

## DONE

| When | What |
|---|---|
| Jul | Sunshine game streaming — reboot-reliable, 4-controller local play |
| Jul | Immich, Dockge, Glances, Homepage stacks |
| Aug 29 | Ollama GPU fix — ~10× faster (was running on CPU) |
| Aug 29 | Open WebUI tuning — task models local, tool overhead cut |
| Aug 30 | Hermes Agent removed entirely (see "Decisions" below) |
| Aug 30 | Caddy + DuckDNS rebuilt — self-built image, works on 443 |
| Aug 30 | Cockpit + Sunshine added behind the proxy |
| Aug 30 | Copilot CLI trialled and rolled back — zero credits spent |
| Aug 30 | Remote access via Tailscale subnet route |
| Aug 30 | Immich phone app moved to the HTTPS name |
| Aug 30 | **moonlight-web-stream deployed** — guest streams the TV from a browser, no install, no password |
| Sep 4 | **Loopback binding** — every published port now binds 127.0.0.1; only Caddy reaches services. Homepage joined the `ai` network to reach Ollama by name. Immich pinned to v3.1.0. |

---

## PENDING — housekeeping, no deadline

- **Credentials live in the password manager.** Rule: no credential exists ONLY on this box — the manager is the source of truth, `.env` files are runtime copies.
- Consider filing the moonlight-web pairing findings upstream — the clean-state requirement
  against Sunshine 2026.516 isn't documented anywhere and cost most of a session.
- ~~Battery charge cap~~ **DONE 2026-08-31.** Was silently at 100% (the old "80% cap"
  never persisted, and the battery is `BAT1`, not `BAT0`). Now capped at 80 by
  `/etc/systemd/system/battery-threshold.service` (glob-based, reboot-persistent,
  verified). Expect the pack to READ 100% for days — the cap stops charging, it
  doesn't drain. `grep . /sys/class/power_supply/BAT*/charge_control_end_threshold` = truth.
- Optional: $15-20 energy-metering smart plug (Kasa/Tapo) — replaces wattage guesses
  with real numbers, and adds remote power-cycle as a last-resort unwedge.
---

## PLANNED / DEFERRED — with triggers

Nothing here gets built without its trigger firing.

| Thing | Trigger |
|---|---|
| **OmniRoute + OpenCode** — free model gateway + second agent | Burning 200 Copilot credits before the 20th of a month |
| **claude-mem** — persistent agent memory | Re-explaining the fx504 setup every session despite an instructions file |
| **Strix** — AI pentesting, your own homelab is a valid target | A free weekend. Costs API credits. Only ever point at systems you own. |
| **Cloudflare Tunnel** — publish a service to the real internet | Needing to share something with a person NOT on the LAN/tailnet (family album, portfolio). Requires redesigning the guest-access model FIRST — the TV streaming path must never go through it as-is. |
| **VLAN segmentation** — homelab on its own subnet | Owning/controlling a VLAN-capable router (likely = own apartment, post-roommates). Precondition: IP-migration checklist — 192.168.x.x is hardcoded in DuckDNS records, WEBRTC_NAT_1TO1_HOST, Sunshine CSRF origins, homepage siteMonitors, Tailscale advertised route, and the roommate's bookmark. Better first exposure: virtual lab (GNS3/containerlab), not the apartment wifi. |
| **Two-way phone control** (Telegram bot / commands) | Wanting to reply to the weekly digest, not just read it |

---

## DECISIONS — why things are the way they are

**No AI agent on the fx504.** Hermes was built and removed in 24 hours. It worked, but only with constant hand-holding — the free-tier model couldn't reliably use its own tools and once reported success for Notion rows it never created. A scheduled report doesn't need a model.

**Invoker lives on the laptop, not the server.** Interactive work happens where you are. The fx504 only needs to run a timer.

**Copilot CLI rolled back, not rejected.** It installed cleanly and everything worked. Removed because there's no Notion workspace, no syllabi and no reporter yet — an agent with nothing to act on is a hobby. Reinstall when there's a workload.

**Tailscale, not Headscale or NetBird.** Both replace the control server, not the client. Same battery, same clients, plus a new service to maintain and a publicly-reachable server you don't have.

**Subnet route is `/32`, not `/22`.** Only the fx504 is reachable over the tailnet, not the whole home network.

**Notion, not Jira/Todoist/self-hosted.** Every row is a full page, so the lecture summary and the deadline live in one object. Schoolwork shouldn't live only on this box.

**NotebookLM for lectures, not Open WebUI knowledge bases.** Grounded answers with citations, 50 chats/day free, purpose-built for this.

---

## THE STANDING RULE

**Measure before building.**

Hermes was built on an assumption and cost six hours. Copilot was installed and removed before a single credit was spent. Both times the fix was the same: get evidence first, then build to fit it.

**The honest test in three weeks:** if you're opening NotebookLM and Notion daily, it worked. If you're mostly opening Dockge and Cockpit, the homelab became the hobby instead of the study system.

---

## COMPANION FILE

`fx504-recovery-cribsheet-v9.md` — keep it. It holds the things you'd have to relearn the hard way: the Sunshine reboot fix, Bazzite recovery, the Caddy build, Notion's data-source quirk, and every "don't do this again" lesson. Reference material, not a status doc.
