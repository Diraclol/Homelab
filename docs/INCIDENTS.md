# fx504 — Audit Log

Machine-readable record of incidents, fixes and hard rules for the fx504 homelab.
Companion to `tracking_fx504.md` (human status). This file is for an AI agent to read.

**Format:** every entry has `SYMPTOM` / `CAUSE` / `FIX` / `RULE`. The `RULE` line is the durable takeaway.
**Append-only.** New incidents go at the bottom of their section with a date.

---

## HARD RULES — never violate

These break things. No exceptions, no "just this once".

```
RULE: NEVER run `docker system prune -a`. Use `docker image prune` (no -a) only.
RULE: NEVER blind-update Immich. Breaking DB migrations, no photo backup exists.
RULE: NEVER update Dockge through its own web UI. CLI only.
RULE: NEVER bulk "update all" containers in Dockge. One at a time.
RULE: NEVER use --yolo / --allow-all / --allow-all-tools with any agent against this host.
RULE: NEVER add a second launcher for Sunshine. The systemd user service is the only one.
RULE: Sunshine is ALWAYS `systemctl --user`, never sudo.
RULE: NEVER edit moonlight-web's server/data.json while the container is running. It holds the
      Sunshine pairing certs; the container overwrites it and you lose both pairings.
```

---

## ENVIRONMENT FACTS

```
HOST: fx504, Asus TUF FX504GD laptop
OS: Bazzite (immutable, rpm-ostree, Fedora-based). /etc writable, /usr not.
CPU: i5-8300H (4c/8t)   RAM: 24GB   GPU: NVIDIA GTX 1050, 2GB VRAM
LAN: 192.168.x.x (wlo1, wifi) | 192.168.x.x (enp3s0, ethernet, preferred metric 100)
TAILSCALE: 100.x.x.x, advertises subnet route 192.168.x.x/32
SSH: user@192.168.x.x
STACKS: /var/mnt/storage/docker/stacks/ — ai, caddy, dockge, glances, homepage, immich, moonlight-web
DATA: 1TB SATA at /var/mnt/storage | 236GB NVMe for OS
FIREWALL: firewalld, desktop default zone (port inventory pass pending)
BATTERY: /sys/class/power_supply/BAT1 (NOT BAT0). AC adapter = ACAD.
         Charge cap 80% via battery-threshold.service (oneshot, glob-based).
SUNSHINE: v2026.516.143833 — the release that introduced web-UI CSRF protection.
          Demands a CLIENT CERTIFICATE (mutual TLS) on 47984 for authenticated
          calls; pairing itself mostly runs over HTTP 47989.
```

**Consequences of the above:**
- Stack dirs are root-owned. `sudo` for every file operation.
- Ports below 1024 need explicit firewalld rules.
- 2GB VRAM means local models above ~1.5B spill to CPU.
- OS auto-updates; a pinned deployment is one reboot-menu pick from undone.

---

## INCIDENTS

### [2026-07-20, refined 07-28] Sunshine dead after every reboot — SOLVED

```
SYMPTOM: Sunshine shows active (running) but port 47990 never binds after boot.
         systemctl status shows Tasks: 0.
CAUSE:   Portal/PipeWire capture context not ready at service start. Sunshine exits
         CLEAN, so Restart=on-failure never fires. Not an encoder problem.
FIX:     Three parts, all needed:
         1. sunshine.conf: encoder=vaapi (NVENC probe HANGS on Pascal+580+Wayland),
            av1_mode=0 (Gen9 iGPU has no AV1), csrf_allowed_origins set.
         2. systemd user override: After= portal/pipewire/wireplumber + ExecStartPre sleep 20.
         3. THE ACTUAL FIX — a health-check timer that tests the PORT, not the process:
            ss -tln | grep -q ":47990 " || systemctl --user restart <unit>
            OnBootSec=45, OnUnitActiveSec=90, Persistent=true
RULE:    Check outcomes (is the port bound), not process state. A clean exit defeats
         Restart=on-failure.
RULE:    Any Sunshine restart takes ~40s to bind. NEVER judge it DOWN before 45s.
RULE:    Restarts must run in the logged-in session — portal screen capture requires it.
         If an SSH restart won't bind, restart from a desktop terminal on the machine.
NOTE:    Recurring idle SIGTRAP coredumps (~daily) are a known flatpak build bug.
         The timer catches them. Ignore unless frequent.
```

### [2026-07] Dockge self-update killed itself — SOLVED

```
SYMPTOM: Dockge tile shows "exited" after updating it from its own web UI.
CAUSE:   Dockge tears itself down mid-update when it is the thing being updated.
FIX:     cd /var/mnt/storage/docker/stacks/dockge && docker compose pull && docker compose up -d
RULE:    Update Dockge from CLI only.
```

### [2026-07] Bulk update wiped user groups — RECOVERED

```
SYMPTOM: After "update all" in Dockge, user lost wheel + docker groups.
         No sudo, no Docker access.
CAUSE:   Bulk container update on Bazzite; group membership is fragile here.
FIX:     Reboot → boot menu → previous ostree deployment → groups restored → pin it.
RULE:    Never bulk-update all containers.
RULE:    Always keep a pinned known-good ostree deployment.
CHECK:   If `groups` shows only user, this happened. Reboot to previous deployment.
```

### [2026-07 → 2026-08-29] Ollama ran on CPU for six weeks — SOLVED

```
SYMPTOM: Local models painfully slow. Assumed the 2GB GPU was too small.
CAUSE:   The ai stack compose file had no `runtime: nvidia`, so the container
         never saw the GPU at all. Misdiagnosed as a hardware limit for 6 weeks.
FIX:     Add to the ollama service: runtime: nvidia,
         NVIDIA_VISIBLE_DEVICES=all, NVIDIA_DRIVER_CAPABILITIES=compute,utility
RESULT:  Prompt eval 77 tok/s → 730-870 tok/s (~10x).
RULE:    A container gets NO GPU unless its compose service says `runtime: nvidia`.
         The daemon having the runtime registered is necessary but NOT sufficient.
RULE:    Before blaming hardware, prove the container can see it:
         docker exec <container> nvidia-smi
NOTE:    OLLAMA_KEEP_ALIVE belongs on the ollama service, not on open-webui.
NOTE:    `ollama ps` showing a CPU/GPU split is expected on 2GB. Not a fault.
```

### [2026-08-29] Silent file-edit failures in stack dirs — SOLVED

```
SYMPTOM: Two edits appeared to succeed but changed nothing. `docker compose up -d`
         then reported success while running the old config.
CAUSE:   (a) plain `cp` failed with Permission denied — stack dirs are root-owned.
         (b) `sudo nano` exited without saving, no error shown.
FIX:     Use the `sudo tee` heredoc pattern for writes.
RULE:    Verify every edit with `ls -la` and `wc -c`. Never trust that an edit took.
RULE:    Run `sudo -v` before pasting multi-line sudo commands over SSH — pasting
         multi-line sudo eats lines.
RULE:    `docker compose up -d` reports success on unchanged/bad configs. It is not
         confirmation that your edit landed.
```

### [2026-08-29] Hermes Agent: script reported success for rows it never created — CAUSE OF TEARDOWN

```
SYMPTOM: notion-create.sh printed "Successfully created row in Notion" for rows
         that did not exist. Hours lost chasing a phantom 401.
CAUSE:   Its success check was `if [ $? -eq 0 ]` on a curl that had already failed.
         That tests whether curl RAN, not whether the API accepted anything.
RULE:    A tool that lies about success is worse than no tool. Any script that
         writes to an API must check the response body, not the exit code.
RULE:    Verify independently when something reports success.
```

### [2026-08-29] Hermes scripts had no API key when run directly — SOLVED (then removed)

```
SYMPTOM: `docker exec hermes sh -c "sh /opt/data/x.sh"` returned HTTP 401
         "API token is invalid". Looked like a revoked token. It wasn't.
CAUSE:   The gateway injects .env only for its OWN tool calls. A bare `docker exec`
         gets a plain shell with an empty NOTION_API_KEY.
RULE:    When a containerised agent runs helper scripts, test THROUGH the agent,
         never with a bare docker exec. Env injection is not global.
```

### [2026-08-30] Caddy could not bind port 443 — SOLVED

```
SYMPTOM: "listen tcp :443: bind: permission denied". Worked fine on 8443.
CAUSE:   The binhex image drops to user `nobody`; cap_add: NET_BIND_SERVICE does
         not survive the privilege drop.
FIX:     Build your own image — FROM caddy:builder + xcaddy --with
         github.com/caddy-dns/duckdns, then COPY the binary into FROM caddy:2.
         Official image runs as root and binds 443 natively.
RULE:    Build the Caddy image yourself. Prebuilt third-party ones drop privileges.
RULE:    Do NOT work around this with net.ipv4.ip_unprivileged_port_start — it is a
         host-level hack that may not survive Bazzite OS updates.
```

### [2026-08-30] HTTPS timed out on 443 while 8443 worked — SOLVED

```
SYMPTOM: Browser timeout (not connection refused) on https://name:443.
CAUSE:   The desktop firewall zone doesn't open ports below 1024 by default,
         and 80 and 443 live there.
FIX:     sudo firewall-cmd --permanent --add-service=http --add-service=https
         sudo firewall-cmd --reload
RULE:    Timeout = firewall dropping packets. Connection refused = nothing listening.
         Different symptoms, different causes. Read which one you got.
```

### [2026-08-30] Local curl to Caddy returned 000 — SOLVED

```
SYMPTOM: curl from the host itself to 127.0.0.1 returned 000. Looked like Caddy
         was broken. It wasn't.
CAUSE:   The inherited `block_world` snippet does `abort` on any non-private remote_ip,
         and Caddy does not treat 127.0.0.1 as private.
FIX:     Remove block_world. Nothing is exposed; the firewall guards the perimeter.
RULE:    Do not use block_world on a LAN-only box. It produces false failure signals.
RULE:    Test Caddy from the LAN IP, not loopback, if block_world is present.
```

### [2026-08-30] Notion queries returned nothing despite rows existing — SOLVED

```
SYMPTOM: Row visible in the Notion UI. API query returned zero results.
CAUSE:   Notion API 2025-09-03 split databases into DATA SOURCES.
         /v1/databases/{id}/query no longer returns rows.
FIX:     Query /v1/data_sources/{data_source_id}/query with Notion-Version 2025-09-03.
         Get the data source ID via retrieve-a-database.
RULE:    Queries need the DATA SOURCE id. Page CREATION still accepts database_id.
         They are different IDs. Do not assume they are the same.
```

### [2026-08-30] Notion Status field read as empty — SOLVED

```
SYMPTOM: Every script reading Status got "-". Board looked completely normal,
         all six options present.
CAUSE:   notion_update_data_source silently converted the property TYPE from
         `status` to `select` while preserving the option names.
FIX:     Read both: pr["Status"].get("status") or pr["Status"].get("select")
RULE:    If a Notion field reads empty, check the property TYPE first, before
         anything else. MCP schema edits can change type without changing appearance.
```

### [2026-08-30] Cockpit "Connection failed" after successful login — SOLVED

```
SYMPTOM: Login page loads over the proxy (HTTP 200), credentials accepted,
         then "Connection failed".
CAUSE:   Cockpit rejects the WebSocket upgrade because the Host header is the
         proxy hostname, not its own.
FIX:     /etc/cockpit/cockpit.conf:
           [WebService]
           Origins = https://cockpit.example.duckdns.org https://192.168.x.x:9090
           ProtocolHeader = X-Forwarded-Proto
         Then: sudo systemctl restart cockpit-container.service
RULE:    Cockpit on Bazzite is a PODMAN QUADLET — the unit is
         cockpit-container.service, NOT cockpit.socket. `systemctl restart
         cockpit.socket` fails with "Unit not found".
RULE:    It runs with -v /:/host so it DOES read the host's /etc/cockpit/cockpit.conf.
         It just needs a restart to pick up changes.
RULE:    Failure AFTER login = origin/WebSocket. Failure BEFORE = proxy or TLS.
```

### [2026-08-30] MCP server added with all tools ate 29% of context — SOLVED

```
SYMPTOM: /context on an empty Copilot CLI session showed 54k/128k tokens used
         before typing anything. MCP Tools alone = 37.5k.
CAUSE:   `copilot mcp add ... notion` defaults to Tools: * (all) — all 41 Notion tools
         loaded into every request.
FIX:     Scope tools explicitly. Only search, fetch, create-pages, update-page and
         query-data-source are ever needed.
RULE:    Any MCP server added with all tools enabled is a permanent tax on every
         request. Always scope.
NOTE:    Same failure shape as Open WebUI injecting builtin tool schemas (2050 tokens
         into a one-word prompt). Disable Builtin Tools per-model for small local models.
```

### [2026-08-30] moonlight-web could not pair with Sunshine — SOLVED after 4 attempts

```
SYMPTOM: Pairing failed repeatedly with THREE different errors across two image versions:
           "failed to pair (stage 2): PairError"
           hyper::Error(IncompleteMessage)
           Os { code: 104, ConnectionReset } at the Connect stage
         Sunshine's own log recorded ZERO pairing attempts throughout.
CAUSE:   Stale pairing state on BOTH sides — this is the decisive cause, proven by
         the fix. Partial entries in Sunshine's client list plus a half-written
         data.json meant the cert exchange never completed, and each retry failed
         differently depending on which half was stale.
         CONTEXT (explains the error variety, is NOT itself the cause): Sunshine
         2026.516 demands a client certificate on 47984 for authenticated calls.
         Proof: curl -k -sv https://127.0.0.1:47984/serverinfo shows "Request
         CERT (13)" then the connection dies after curl sends an empty 8-byte
         Certificate. Port 47989 (HTTP) answers fine. Most of the Moonlight
         pairing exchange runs over HTTP 47989; the mTLS port only explains the
         IncompleteMessage / ConnectionReset errors (47984 rejecting an
         unrecognized cert), not why pairing itself failed. "Pairing requires
         mTLS" is an overstatement — do not carry it into a bug report.
FIX:     Full clean state on both sides, in this order:
         1. docker compose down
         2. rm -rf server/*        (wipes config.json + data.json)
         3. Sunshine web UI → Troubleshooting → Unpair All Clients
         4. docker compose up -d
         5. Log in, add host `localhost` (port empty), pair, PIN into Sunshine promptly
RULE:    When pairing fails more than twice, STOP retrying and reset BOTH sides
         together. Retrying against half-stale state produces different errors each
         time and sends you chasing the wrong cause.
RULE:    Sunshine's client cert lives INSIDE server/data.json, not as a separate .pem.
         A successful pair shows up as data.json growing (~3.4KB → ~5.2KB), not as a
         new file. Do not conclude "no cert was generated" from an ls.
RULE:    Version-mismatch is the WRONG first hypothesis here. v2.10.0 and :latest failed
         identically. Check protocol-level evidence (curl the endpoint) before swapping
         images.
NOTE:    Each moonlight-web USER is a separate Moonlight client id to Sunshine.
         admin and guest each need their own pairing. Pairing does not transfer
         between users.
NOTE:    If filing upstream (MrCreativ3001/moonlight-web-stream): lead with the
         dual-side clean-state requirement and the three misleading error shapes,
         not mTLS. That is what a maintainer can act on.
```

### [2026-08-30] moonlight-web browser auto-login did nothing — SOLVED

```
SYMPTOM: Guest auto-login configured, container restarted clean, still a login box.
CAUSE:   Two separate blockers, found one after the other.
         (a) The guest account's stored state didn't match what auto-login requires.
             The web UI cannot express the required state; only a config edit can.
         (b) After moving behind HTTPS via Caddy, the session cookie had to be marked
             Secure or the app re-prompted. Empirical (reboot-tested twice), and not
             standard cookie semantics — app-level behaviour, not browser policy.
FIX:     Stop the container, correct the account state and the cookie flag in the
         server config, start it. Test in a PRIVATE window: an old cookie masks the result.
RULE:    Changing the access path (HTTP → HTTPS) changes the cookie-security flag.
         Re-check it whenever the proxy changes.
RULE:    When a UI can't express a config state, the app's schema still can. Read the
         schema, then edit — with the container STOPPED (it rewrites the file on exit).
```

### [2026-08-30] Editing container-written JSON failed with Permission denied — SOLVED

```
SYMPTOM: python3 edit of server/config.json → PermissionError [Errno 13].
         The subsequent `docker compose restart` "succeeded", masking the failure.
CAUSE:   Container runs as a non-root UID that maps to polkitd:ssh_keys on the host.
         Bind-mounted files it creates are not writable by user.
FIX:     Give the host user write access to the two config files (the container's
         UID owns them).
RULE:    ALWAYS grep the file after editing it to confirm the change landed. A restart
         after a failed edit looks identical to a restart after a successful one.
```

### [2026-08-30] Sunshine web UI refused saves from the proxied name — SOLVED

```
SYMPTOM: "CSRF Protection Error" on stream.example.duckdns.org. Saves and PIN entry
         silently did nothing.
CAUSE:   csrf_allowed_origins listed only https://192.168.x.x:47990. Sunshine
         2026.516 added CSRF protection; any non-localhost origin must be declared.
FIX:     csrf_allowed_origins = https://192.168.x.x:47990,https://stream.example.duckdns.org
         COMMA-separated. Each entry a full URL prefix with scheme. Port optional.
         Restart Sunshine, allow 45s to bind.
RULE:    A CSRF rejection is INVISIBLE — no UI error, nothing in sunshine.log. If a save
         appears to do nothing at all, suspect this first and check dev tools for a 400.
RULE:    Every new hostname pointed at Sunshine's web UI needs adding here. Adding a
         Caddy route is only half the job.
```

### [2026-08-30] Stream went black mid-session — EXPECTED, not a fault

```
SYMPTOM: Browser tab alive, stream area completely black.
CAUSE:   Sunshine restarted underneath the session — "[pipewire] Pipewire Error ...
         connection error" followed by a fresh "Starting main loop". The health-check
         timer did its job; the browser just kept an orphaned tab.
FIX:     Relaunch the stream. A full reboot clears PipeWire/portal state properly.
RULE:    A black stream with a live tab means the SERVER restarted, not that the
         network failed. Check sunshine.log for a fresh startup banner before
         touching anything network-related.
```

### [2026-08-31] Battery charge cap believed set, battery at 100% — SOLVED

```
SYMPTOM: Crib sheet said "battery cap 80%"; pack sat at 100% for months on 24/7 AC.
         First fix attempt also "printed 80" yet the file read back No such file.
CAUSE:   Two layers.
         (a) The original cap never persisted (or was never applied) — sysfs
             resets on reboot and nothing re-applied it.
         (b) The fix wrote to literal BAT0. This machine's battery is BAT1.
             The read used a glob (BAT*) and worked; the write used a literal
             and failed. `tee` still echoed "80" to stdout — that was tee
             repeating its stdin, not the file's value. The real verdict was
             the "No such file or directory" line above it.
FIX:     /etc/systemd/system/battery-threshold.service — oneshot, enabled,
         writes 80 via a glob loop so the battery name never matters:
           for f in /sys/class/power_supply/BAT*/charge_control_end_threshold;
             do echo 80 > "$f"; done
         Verified: grep . BAT*/charge_control_end_threshold → 80.
RULE:    tee prints its stdin even when the write FAILS. The echoed value is
         not confirmation; the presence/absence of an error line is.
RULE:    Never read with a glob and write with a literal. Same path form for
         both, or the read masks the write's failure.
RULE:    A sysfs setting without a persistence unit is temporary by definition.
         "I set it once" means "it lasted until the next reboot."
NOTE:    Battery will SIT at 100% for days after this — the cap stops charging
         above 80, it does not drain. grep is ground truth, not the icon.
```

---

## DIAGNOSIS SHORTCUTS

```
Sunshine up?        ss -tlnp | grep 47990 && echo UP || echo DOWN
                    (ground truth — NOT the Homepage tile. Wait 45s after any restart.)
GPU visible?        docker exec ollama nvidia-smi
GPU actually used?  docker exec ollama ollama ps   → read the PROCESSOR column
Caddy ports?        sudo ss -tlnp | grep -E ':(80|443) '
Caddy config ok?    docker exec caddy caddy validate --config /etc/caddy/Caddyfile
Sunshine mTLS?      curl -k -sv https://127.0.0.1:47984/serverinfo 2>&1 | head -25
                    ("Request CERT" then death = normal, it wants a client cert)
Sunshine API alive? curl -s "http://127.0.0.1:47989/serverinfo?uniqueid=0123456789ABCDEF"
                    (returns XML — the honest "is Sunshine actually serving" test)
Battery cap live?   grep . /sys/class/power_supply/BAT*/charge_control_end_threshold  → :80
Proxy path works?   curl -s -o /dev/null -w "%{http_code}\n" \
                      -H "Host: home.example.duckdns.org" https://192.168.x.x/
Groups intact?      groups        (only "user" = the Dockge bulk-update incident)
Disk?               df -h /var/mnt/storage
Reclaim space?      docker image prune        (NEVER system prune -a)
```

---

## KNOWN NON-PROBLEMS — do not investigate

```
Sunshine SIGTRAP coredumps when idle    → known flatpak build bug, timer catches it
Moonlight low FPS on idle desktop       → damage-based capture, normal. Judge in-game.
`caddy fmt` "input is not formatted"    → spurious; file IS formatted, config is read-only
KDE "limited connectivity"              → cries wolf, verify with ping
SELinux/setroubleshootd transient fails → cosmetic Fedora noise
hid-playstation DualSense probe errors  → harmless on clone controllers
Cockpit "couldn't connect: No such file"→ routine session cleanup
Glances Intel-GPU metric wrong          → unreliable in-container, ignore
ollama ps showing CPU/GPU split         → expected on 2GB VRAM
moonlight-web ICE "missing transport"   → logged during teardown, harmless
Sunshine "Failed to gain CAP_SYS_ADMIN" → flatpak cannot do KMS capture, portal is used
av1_vaapi "No usable encoding profile"  → Gen9 iGPU has no AV1, already av1_mode=0
composefs / at 100% in df or file mgr  → Bazzite's read-only 45MB immutable root.
                                          ALWAYS full by design. Check /var and
                                          /var/mnt/storage for real disk usage.
```

---

## DISASTER RECOVERY

### A. OS broken, data drive fine (most likely case)

```
1. Boot menu → previous pinned deployment, OR: rpm-ostree rollback
   Fresh install = bazzite-nvidia, Secure Boot OFF.
2. Re-layer Docker, fix docker group, recreate daemon.json,
   nvidia-ctk runtime configure, restart docker.
3. Re-add fstab line for the 1TB (UUID <UUID>), daemon-reload && mount -a
4. cd /var/mnt/storage/docker/stacks/dockge && docker compose up -d
   → deploy remaining stacks from the Dockge UI. Data is on the 1TB, so it returns.
5. Sunshine: reinstall flatpak + additional-install.sh + enable user service.
   Re-apply CSRF origin, VA-API config, boot-delay override AND health-check timer.
   Re-pair Moonlight.
6. Network: recreate powersave conf + sysctl. Re-advertise Tailscale route
   (192.168.x.x/32) and approve it.
7. VERIFY the ai stack still has `runtime: nvidia` — without it Ollama silently
   runs on CPU and you will not notice for weeks.
8. Caddy: rebuild the image (docker compose build), restore .env with the
   DuckDNS token, open http/https in firewalld.
9. moonlight-web: deploy stack, re-apply the guest-account and cookie settings from
   the private notes, then re-pair admin AND guest separately from a fully clean
   Sunshine client list.
```

### B. 1TB drive died

```
Photos are unrecoverable (accepted risk, no backup).
Everything else is rebuildable from this file.
Schoolwork is unaffected — it lives in Notion, off this machine.
```

### C. Single container misbehaving

```
Dockge → logs first.
cd <stack folder> && docker compose up -d --force-recreate
Immich specifically → check DB_PASSWORD and library/backups/
```

---

## REJECTED OPTIONS — do not re-evaluate without new information

```
Apollo (Sunshine fork)      → virtual-display feature is Windows-only. Only reconsider
                              if this host ever moves to Windows.
NVENC encoder               → probe HANGS on Pascal + driver 580 + Wayland. VA-API is final.
Headscale / NetBird         → replace the control server, not the client. Same battery,
                              new service to maintain, needs a publicly reachable host.
Jira / Todoist / self-hosted
  trackers                  → Jira is team ceremony for a solo list. Todoist has no notes.
                              Self-hosted means schoolwork lives on this box. All rejected.
Local LLMs for agent work   → 2GB VRAM. llama3.2:1b and qwen2.5:1.5b cannot do reliable
                              tool calling, which is the entire job.
Routing Copilot through
  a gateway                 → same credits, no gain, and it is the pattern that got
                              third-party tools cut off from Claude subscriptions in Jan 2026.
Anime streaming apps        → piracy sources. Jellyfin is the legitimate option.
```

---

## RATE LIMITS AND QUOTAS — verified, not from blogs

```
Gemini 3.7 Flash        5 RPM  · 250K TPM · 20 requests per DAY
Gemini 3.5 Flash Lite  15 RPM  · 250K TPM · 500 per day   ← the sensible default
Gemma 4 31b            30 RPM  ·  16K TPM · not usable for documents (TPM too low)
Copilot Student        200 AI credits/month, resets on the 31st.
                       Code completions unlimited. Auto-model-only, no model choice.
                       Additional-usage budget defaults to $0 and disabled.
NotebookLM free        100 notebooks · 50 sources each · 50 chats/day
Claude Code            NO free path. Subscription or API billing only.
```

**RULE: Gemini limits are per Google Cloud PROJECT, not per API key.** Extra keys on the same project do not help. RPD resets midnight Pacific. Read them off AI Studio's rate-limits page, never a blog post.
