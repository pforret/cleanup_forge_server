# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Bash script to clean Laravel Forge servers after a security breach. Designed to run as the `forge` user from `/home/forge`. Single file: `cleanup_forge.sh`.

## Architecture

The script runs sequentially through these phases:

1. **Crontab cleanup** — removes entries referencing `/var/tmp`, `/dev/shm`, `/tmp`
2. **Process kill** — terminates known malicious process patterns (crypto miners, reverse shells)
3. **Temp directory purge** — removes forge-owned files from `/var/tmp` and `/dev/shm`
4. **Per-site cleanup** (iterates `/home/forge/*/` git repos):
   - Logs untracked/modified files, then `git reset --hard` + `git clean -df`
   - Removes PHP files from `storage/` (excluding compiled views)
   - Removes PHP files from upload directories
   - Removes hex-named/known-webshell PHP files from `public/`
   - Scans remaining PHP for dangerous function signatures (report only)
5. **Post-run** — writes timestamped log to `/home/forge/cleanup_*.log`, prints manual remediation checklist

## Development

No build, test, or lint tooling. To check syntax: `bash -n cleanup_forge.sh`

Target environment: Linux servers managed by Laravel Forge, using standard coreutils + git.
