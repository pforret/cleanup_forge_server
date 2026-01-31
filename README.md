# cleanup_forge_server

Bash script to clean Laravel Forge servers after a security breach. Removes webshells, crypto miners, malicious cron jobs, and restores git-tracked sites to a known-good state.

## What it does

1. **Crontab cleanup** — removes entries referencing `/var/tmp`, `/dev/shm`, `/tmp`
2. **Process kill** — terminates known malicious processes (crypto miners, reverse shells)
3. **Temp directory purge** — removes forge-owned files from `/var/tmp` and `/dev/shm`
4. **Per-site cleanup** (for each git repo in `/home/forge/*/`):
   - Logs untracked/modified files
   - Runs `git reset --hard` + `git clean -df`
   - Removes PHP files from `storage/` (excluding compiled views)
   - Removes PHP files from upload directories
   - Removes hex-named and known-webshell PHP files from `public/`
   - Scans remaining PHP for dangerous function signatures (report only)
5. **Post-run** — writes timestamped log, prints manual remediation checklist

## Requirements

- Linux server managed by [Laravel Forge](https://forge.laravel.com/)
- Standard coreutils + git
- Must run as the `forge` user

## Usage

```bash
ssh forge@your-server
cd /home/forge
bash cleanup_forge.sh
```

The script writes a timestamped log to `/home/forge/cleanup_YYYYMMDD_HHMMSS.log`.

## After running

The script will remind you to:

1. Rotate all `.env` credentials on every site
2. Run `php artisan key:generate` on every site
3. Rotate database passwords
4. Check nginx logs for the entry vector
5. Consider a full server rebuild via Forge
