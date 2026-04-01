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

## Key principles

- **No magic** — everything is based on rsync
- **Predictability** — dry-run before every restore
- **Separation** — system and Docker handled independently
- **Minimal overhead** — hardlink-based deduplication

---

## TL;DR

- snapshots via `rsync + --link-dest`
- near-instant creation
- minimal disk usage
- safe restore with preview
- systemd automation support

---

## Quick Start (2–3 minutes)

```bash
git clone <repo>
cd ext4-rollback-tool

# configure
cp config/.env.example config/.env

# enable automation
chmod +x bin/apply-timers.sh
sudo ./bin/apply-timers.sh

# create first snapshot
sudo ./bin/snapshot-system.sh
```

---

## Basic usage

### Create snapshots

```bash
sudo ./bin/snapshot-system.sh
sudo ./bin/snapshot-docker.sh
```

### Restore

```bash
sudo ./bin/restore-system.sh
sudo ./bin/restore-docker.sh
```

All restore operations:

- start with dry-run
- show file changes and deletions
- require explicit confirmation

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

- [Snapshots](docs/snapshots.md)
- [Restore process](docs/restore.md)
- [Configuration](docs/configuration.md)
- [Timers](docs/timers.md)
- [Safety](docs/safety.md)

---

## When to use this

- you broke system config
- update failed
- docker stopped working
- you want safe rollback without reinstall

---

## License

MIT
