# systemd units

Copy the unit files from `/etc/systemd/system/` on the host:

- `battery-threshold.service` — caps charging at 80% on `BAT1`, glob-based, reboot-persistent
- the Sunshine health-check `.service` + `.timer` — checks the listening socket, not process state

`build_repo.sh` copies these from the host and scrubs them; check REVIEW.md afterwards.
