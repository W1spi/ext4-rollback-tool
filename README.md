# ext4-rollback-tool

Rollback-oriented snapshot toolkit for Linux hosts on ext4, built on top of rsync with hardlink deduplication (`--link-dest`).

---

## Overview

This tool provides a **fast and controlled rollback mechanism** for Linux systems using ext4.

It is designed for situations where:

- you broke system configuration
- an update went wrong
- docker infrastructure stopped working
- you want predictable rollback without switching filesystem

---

## Why this project exists

Most snapshot solutions assume:

- Btrfs or ZFS
- LVM snapshots
- backup systems (borg, restic, etc.)

But in real setups:

- ext4 is still the default
- migrating filesystem is often not possible
- backup tools are too heavy for rollback use-cases

This tool solves:

> fast, local, predictable rollback on ext4

---

## Important: this is NOT a backup tool

This tool:

- restores system state
- helps recover from mistakes
- works locally and quickly

This tool does NOT:

- protect from disk failure
- protect from ransomware
- replace off-site backups

---

## Core concepts

### Rollback vs Backup

Rollback:
- fast
- local
- restores current system state

Backup:
- long-term storage
- disaster recovery

This project is strictly about rollback.

---

### Separation of concerns

System and Docker are handled independently:

- system snapshot → full OS
- docker snapshot → infrastructure only

This prevents:

- unnecessary data duplication
- accidental overwrites
- slow restores

---

## Project structure
ext4-rollback-tool/
├── bin/
├── config/
├── systemd/
├── README.md
├── README.ru.md
├── LICENSE

---

## Snapshot storage structure
.infra_snapshots/
├── docker/
│ ├── <timestamp>/
│ └── LATEST
├── system/
│ ├── <timestamp>/
│ └── LATEST
└── _logs/

Each snapshot looks like a full copy, but only changed files are stored.

---

## How snapshots work

1. Create temporary directory:
.tmp-YYYY-MM-DD_HH-MM-SS


2. Run rsync:
- `--link-dest` → deduplication
- only changed files are copied

3. Rename temp → final

4. Update `LATEST` symlink

---

## Configuration

All configuration is done via `.env` files.

Create them:
cp config/.env.example config/.env

---

## Environment variables

### snapshot-docker.env

| Variable | Description |
|--------|-------------|
| DEST_BASE | Where snapshots are stored |
| KEEP_COUNT | Number of snapshots to keep |
| DOCKER_PROJECTS_DIR | Docker projects directory |
| DOCKER_ETC_DIR | /etc/docker path |

---

### snapshot-system.env

| Variable | Description |
|--------|-------------|
| DEST_BASE | Snapshot storage |
| KEEP_COUNT | Number of snapshots |
| SRC | Source (usually /) |

---

### restore-docker.env

| Variable | Description|
|--------|-------------	|
| SNAP_BASE | Snapshot storage|
| LOG_DIR | Restore logs |
| PROJECTS_DST | Docker projects restore path |
| ETC_DOCKER_DST | Docker config restore path |

---

### restore-system.env

| Variable | Description |
|--------|-------------|
| SNAP_BASE | Snapshot storage |
| LOG_DIR | Restore logs |

---

## Usage

### Create snapshots

sudo ./bin/snapshot-docker.sh
sudo ./bin/snapshot-system.sh

---

### Restore Docker

sudo ./bin/restore-docker.sh

Flow:

1. Select snapshot
2. Dry-run
3. Confirm
4. Stop Docker
5. Restore files
6. Start Docker

---

### Restore system

sudo ./bin/restore-system.sh


Flow:

1. Select snapshot
2. Dry-run (mandatory)
3. Show deletions
4. Double confirmation
5. Restore `/`

Reboot recommended.

---

## Timers

The project uses systemd timers to run snapshots automatically on a schedule.

Timers are generated from the configuration file:

config/timers.env

###How it works

snapshot-system.timer → triggers system snapshots
snapshot-docker.timer → triggers Docker snapshots
each timer runs its corresponding .service, which executes the snapshot script

The timers are created and applied using:

sudo ./bin/apply-timers.sh

###Configuration

You can configure schedules in:

config/timers.env

Example:

SYSTEM_ON_CALENDAR=Sun *-*-* 00:30:00
DOCKER_ON_CALENDAR=*-*-* 23:30:00

Common patterns:

*-*-* 23:30:00 → every day at 23:30
Sun *-*-* 00:30:00 → every Sunday at 00:30
*-*-01 02:00:00 → first day of every month at 02:00

###First run (important)

Before using timers, make the script executable and apply configuration:

chmod +x bin/apply-timers.sh
sudo ./bin/apply-timers.sh

This will:

generate systemd timer files
reload systemd
enable and start timers

###After changing schedule

If you modify config/timers.env, you must reapply timers:

sudo ./bin/apply-timers.sh

Otherwise, systemd will continue using the old schedule.

Behavior
timers run automatically after system reboot
missed runs are executed after startup (Persistent=true)
no manual interaction is required after initial setup

###Check timers

systemctl list-timers

###Manual run

You can trigger snapshots manually:

systemctl start snapshot-system.service
systemctl start snapshot-docker.service

---

## Understanding rsync dry-run output

Example:

f.st......

Meaning:

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

f.st...... file.txt
File will be updated (size + timestamp changed)

*deleting path/to/file
File will be deleted

---

## Safety recommendations

- ALWAYS check dry-run
- NEVER ignore *deleting output
- do not run system restore blindly
- store snapshots on separate disk if possible

---

## Use cases

- broken configs
- failed updates
- docker environment issues
- infrastructure rollback

---

## Limitations

- no disk failure protection
- no offsite backup
- not for long-term storage

---

## Future plans

- flexible snapshot profiles
- include/exclude configuration
- unified CLI
- install script

---

## License

MIT
