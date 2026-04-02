# Changelog

All notable changes to this project will be documented in this file.

---

## [Unreleased]

### Added

* SNAP_ROOT architecture for unified snapshot storage
* systemd service + timer integration
* fallback scheduler for non-systemd environments
* .env.example templates for all scripts

### Changed

* replaced hardcoded paths with env-based configuration
* improved snapshot scripts portability
* unified project structure and configuration model

### Improved

* restore UX (dry-run, previews, confirmations)
* safety checks before system restore
* logging and observability
* systemd timer reliability (persistent + randomized delay)

### Removed

* hardcoded infrastructure paths
* legacy scheduler as primary mechanism

---

## Notes

This refactor transforms the project into a portable,
environment-configurable, production-ready snapshot tool.
