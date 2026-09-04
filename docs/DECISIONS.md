# Decisions

Short "why" entries. Each is a decision that could reasonably have gone another way.

**Tailscale, not Headscale or NetBird.** Both replace the control server, not the client —
same battery, same clients, plus a new service to maintain and a publicly-reachable server I
don't have.

**Subnet route is `/32`, not `/22`.** Only this host is reachable over the tailnet, not the
whole home network.

**DNS-01 wildcard, not per-service HTTP-01.** One certificate, no inbound port 80, and no
service is ever exposed to get a cert.

**Immutable OS.** Recovery is `rpm-ostree rollback`, not a reinstall. Worth the friction of
layering packages.

**Custom Caddy build.** The pre-built image with the DNS plugin could not bind 443 as
non-root; building with `xcaddy` fixed it in one afternoon and pinned the plugin version.

**No AI agent on the host.** Built one, measured it for 24 hours, removed it. It needed
constant hand-holding and once reported success on work it never did. Measure before building.

**Notion + NotebookLM for coursework, not self-hosted tools.** Schoolwork shouldn't live only
on this box.
