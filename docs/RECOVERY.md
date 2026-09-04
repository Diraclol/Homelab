# Recovery runbook

<!-- TODO: build_repo.sh replaces this file with your recovery cribsheet (scrubbed) if it finds one.
     Otherwise paste it here and check REVIEW.md. Keep the order — it is a checklist, not a reference. -->

Sections to keep:

1. OS rollback (`rpm-ostree rollback`) and when to use it
2. Docker + NVIDIA runtime reinstall on a fresh image
3. Tailscale re-join and subnet route re-approval
4. Caddy stack: DuckDNS credentials from the credential manager → `.env` → `docker compose up`
5. Stack redeploy order (proxy first, then dashboard, then everything else)
6. Sunshine / Moonlight re-pairing
7. Immich database restore from backup
8. Verification checklist (every hostname resolves and serves a valid cert)
