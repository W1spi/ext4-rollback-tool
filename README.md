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

## Quick Start (2–3 minutes)

```bash
git clone git@github.com:W1spi/ext4-rollback-tool.git
cd ext4-rollback-tool

# prepare config files
cp config/snapshot-system.env.example config/snapshot-system.env
cp config/snapshot-docker.env.example config/snapshot-docker.env
cp config/restore-system.env.example config/restore-system.env
cp config/restore-docker.env.example config/restore-docker.env
cp config/timers.env.example config/timers.env

# review paths and retention
nano config/snapshot-system.env
nano config/snapshot-docker.env
nano config/restore-system.env
nano config/restore-docker.env
nano config/timers.env

# enable timers
chmod +x bin/apply-timers.sh
sudo ./bin/apply-timers.sh

# create first snapshots
sudo ./bin/snapshot-system.sh
sudo ./bin/snapshot-docker.sh
```

---

## Automation (systemd timers)

Snapshots can run automatically via systemd timers.

Example schedule:

```
SYSTEM_ON_CALENDAR=Sun *-*-* 00:30:00
DOCKER_ON_CALENDAR=*-*-* 23:30:00
```

Apply configuration:

```bash
sudo ./bin/apply-timers.sh
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
