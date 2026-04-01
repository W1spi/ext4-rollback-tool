# ext4-rollback-tool

Rollback-oriented snapshot toolkit for Linux hosts on ext4, built on top of rsync with hardlink deduplication (`--link-dest`).

---

## Overview

ext4-rollback-tool is a **lightweight and predictable rollback system** designed for Linux environments where ext4 is used as the primary filesystem.

It allows you to:

- quickly capture system state
- safely roll back after failures
- avoid heavy snapshot solutions (ZFS/Btrfs/LVM)

> Built for engineers who want control, simplicity, and transparency.

---

## Why this project exists

Most snapshot tools assume:

- Btrfs or ZFS
- LVM snapshots
- full backup systems (borg, restic, etc.)

But in real-world setups:

- ext4 is still the default
- filesystem migration is often impossible
- backup tools are too heavy for quick rollback

This project solves:

> **fast, local, predictable rollback on ext4 without changing filesystem**

---

## Important: this is NOT a backup tool

This tool:

- restores system state
- helps recover from mistakes
- operates locally and quickly

This tool does NOT:

- protect from disk failure
- protect from ransomware
- replace off-site backups

---

## Core concepts

### Rollback vs Backup

| Rollback | Backup |
|--------|--------|
| fast | slow |
| local | remote |
| current state recovery | long-term storage |
| minimal overhead | complex systems |

This project is strictly about rollback.

---

### Separation of concerns

System and Docker are handled independently:

- **system snapshot** → full OS
- **docker snapshot** → infrastructure only

Benefits:

- no unnecessary duplication
- faster snapshots
- safer restores

---

## How snapshots work

Each snapshot is created using rsync with hardlink deduplication:

```bash
rsync -a --delete --link-dest=PREVIOUS_SNAPSHOT
```

### Snapshot flow

1. Create temporary directory:
```
.tmp-YYYY-MM-DD_HH-MM-SS
```

2. Run rsync:
- only changed files are copied
- unchanged files are hardlinked

3. Rename temp → final snapshot

4. Update `LATEST` symlink

### Result

Each snapshot looks like a full copy, but:

- unchanged files = hardlinks
- disk usage stays low
- restore is fast and predictable

---

## Project structure

```
ext4-rollback-tool/
├── bin/              # scripts
├── config/           # env configs
├── systemd/          # services & timers
├── README.md
├── README.ru.md
├── LICENSE
```

---

## Snapshot storage structure

```
.infra_snapshots/
├── docker/
│   ├── <timestamp>/
│   └── LATEST
├── system/
│   ├── <timestamp>/
│   └── LATEST
└── _logs/
```

---

## Configuration

All configuration is done via `.env` files.

```bash
cp config/.env.example config/.env
```

---

## Environment variables

### snapshot-docker.env

| Variable | Description |
|--------|-------------|
| DEST_BASE | snapshot storage |
| KEEP_COUNT | number of snapshots |
| DOCKER_PROJECTS_DIR | docker projects path |
| DOCKER_ETC_DIR | /etc/docker path |

---

### snapshot-system.env

| Variable | Description |
|--------|-------------|
| DEST_BASE | snapshot storage |
| KEEP_COUNT | number of snapshots |
| SRC | source path (usually `/`) |

---

### restore-docker.env

| Variable | Description |
|--------|-------------|
| SNAP_BASE | snapshot storage |
| LOG_DIR | restore logs |
| PROJECTS_DST | docker projects destination |
| ETC_DOCKER_DST | docker config destination |

---

### restore-system.env

| Variable | Description |
|--------|-------------|
| SNAP_BASE | snapshot storage |
| LOG_DIR | restore logs |

---

## Usage

### Create snapshots

```bash
sudo ./bin/snapshot-docker.sh
sudo ./bin/snapshot-system.sh
```

---

### Restore Docker

```bash
sudo ./bin/restore-docker.sh
```

Flow:

1. Select snapshot
2. Dry-run
3. Confirm
4. Stop Docker
5. Restore files
6. Start Docker

---

### Restore system

```bash
sudo ./bin/restore-system.sh
```

Flow:

1. Select snapshot
2. Dry-run (**mandatory**)
3. Review deletions
4. Double confirmation
5. Restore `/`

> Reboot is recommended after restore

---

## Automation (systemd timers)

Snapshots can run automatically using systemd timers.

### How it works

- `snapshot-system.timer` → system snapshots
- `snapshot-docker.timer` → docker snapshots
- each timer triggers corresponding `.service`

---

### Setup

```bash
chmod +x bin/apply-timers.sh
sudo ./bin/apply-timers.sh
```

This will:

- generate timer files
- reload systemd
- enable timers

---

### Configuration

Edit:

```
config/timers.env
```

Example:

```
SYSTEM_ON_CALENDAR=Sun *-*-* 00:30:00
DOCKER_ON_CALENDAR=*-*-* 23:30:00
```

Common patterns:

- `*-*-* 23:30:00` → daily
- `Sun *-*-* 00:30:00` → weekly
- `*-*-01 02:00:00` → monthly

---

### After changes

```bash
sudo ./bin/apply-timers.sh
```

---

### Behavior

- runs automatically after reboot
- missed runs are executed (`Persistent=true`)
- no manual interaction required

---

### Check timers

```bash
systemctl list-timers
```

---

### Manual trigger

```bash
systemctl start snapshot-system.service
systemctl start snapshot-docker.service
```

---

## Understanding rsync dry-run output

Example:

```
f.st......
```

### Legend

| Symbol | Meaning |
|------|--------|
| f | file |
| d | directory |
| L | symlink |
| s | size changed |
| t | timestamp changed |
| c | checksum changed |
| + | new file |
| *deleting | will be removed |

---

### Examples

```
f.st...... file.txt
```
→ file updated

```
*deleting path/to/file
```
→ file will be deleted

---

## Safety recommendations

- ALWAYS check dry-run
- NEVER ignore `*deleting`
- do not restore system blindly
- store snapshots on separate disk if possible

---

## Use cases

- broken configs
- failed updates
- docker issues
- infrastructure rollback

---

## Limitations

- no disk failure protection
- no offsite backup
- not for long-term storage

---

## Future plans

- flexible snapshot profiles
- include/exclude rules
- unified CLI
- install script

---

## License

MIT
