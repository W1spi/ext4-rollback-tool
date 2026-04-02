# ext4-rollback-tool

Rollback-oriented snapshot toolkit for Linux hosts on ext4, built on top of rsync with hardlink deduplication (`--link-dest`).

---

## Overview

ext4-rollback-tool is a **lightweight and predictable rollback system** designed for Linux environments where ext4 is used as the primary filesystem.

It allows you to:

- capture system state in seconds
- safely recover from broken configurations or updates
- rollback Docker infrastructure independently
- avoid heavy snapshot technologies (Btrfs, ZFS, LVM)

> This tool focuses on **control, transparency and reliability**, not abstraction.

---

## Why this project exists

Most snapshot solutions assume:

- modern filesystems (Btrfs / ZFS)
- LVM-based setups
- full-featured backup systems (borg, restic, etc.)

However, in real-world environments:

- ext4 is still the default
- migrating filesystem is often not possible
- backup tools are too heavy for quick rollback scenarios

This project solves:

> **fast, local and predictable rollback on ext4 without changing your stack**

---
## Quick Start (1–2 minutes)

```bash
git clone git@github.com:W1spi/ext4-rollback-tool.git
cd ext4-rollback-tool

# prepare config (defaults are safe)
cp config/*.env.example config/*.env

# enable timers
chmod +x bin/apply-timers.sh
sudo ./bin/apply-timers.sh

# create first snapshots (optional)
sudo ./bin/snapshot-system.sh
sudo ./bin/snapshot-docker.sh
```

### That’s it.

Snapshots are now:

* automatically scheduled via systemd
* stored under `/var/backups/ext4-rollback`
* ready for restore at any time

---

### Project location

The project directory can be placed anywhere:

* `/opt/ext4-rollback-tool`
* `/home/user/ext4-rollback-tool`
* or any other location

There are no hardcoded paths — all behavior is controlled via configuration files.

---

### Optional: customize configuration

If you want to adjust paths, retention or schedules:

```bash
nano config/snapshot-system.env
nano config/snapshot-docker.env
nano config/timers.env
```

---

## Important

This is **not a backup tool**.

It does NOT:

- protect from disk failure
- protect from ransomware
- replace off-site backups

It is designed purely for:

> **fast rollback of local system state**

---

## Documentation

Detailed documentation:

- [Snapshots](docs/snapshots_ru.md)
- [Restore process](docs/restore_ru.md)
- [Configuration](docs/configuration_ru.md)
- [Safety](docs/safety_ru.md)

---

## When to use this

- you broke system config
- update failed
- docker stopped working
- you want safe rollback without reinstall

---

## License

MIT
