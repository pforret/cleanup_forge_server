#!/bin/bash
## cleanup_forge.sh — run as forge user from /home/forge
## Cleans all Laravel sites of webshells and suspect files

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
fail() { echo -e "${RED}[XX]${NC} $1"; }

FORGE_HOME="/home/forge"
LOGFILE="$FORGE_HOME/cleanup_$(date +%Y%m%d_%H%M%S).log"

echo "=== Forge Server Cleanup — $(date) ===" | tee "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# 1. Clean crontab
echo "--- Checking crontab ---" | tee -a "$LOGFILE"
if crontab -l 2>/dev/null | grep -q "/var/tmp\|/dev/shm\|/tmp/"; then
    fail "Malicious crontab found, removing:" | tee -a "$LOGFILE"
    crontab -l 2>/dev/null | tee -a "$LOGFILE"
    crontab -r
    log "Crontab cleared" | tee -a "$LOGFILE"
else
    log "Crontab clean" | tee -a "$LOGFILE"
fi

# 2. Kill suspect processes
echo "" | tee -a "$LOGFILE"
echo "--- Killing suspect processes ---" | tee -a "$LOGFILE"
for pattern in DHrLgBEnK "perl /var/tmp" "perl /tmp" "perl /dev/shm" "python /var/tmp" "python /tmp"; do
    if pgrep -f "$pattern" >/dev/null 2>&1; then
        fail "Killing: $pattern" | tee -a "$LOGFILE"
        pkill -f "$pattern" 2>/dev/null || true
    fi
done
log "Suspect processes handled" | tee -a "$LOGFILE"

# 3. Clean temp directories
echo "" | tee -a "$LOGFILE"
echo "--- Cleaning temp directories ---" | tee -a "$LOGFILE"
for dir in /var/tmp /dev/shm; do
    find "$dir" -type f -user forge 2>/dev/null | while read -r f; do
        fail "Removing $f" | tee -a "$LOGFILE"
        rm -f "$f"
    done
done
log "Temp directories cleaned" | tee -a "$LOGFILE"

# 4. Process each site
echo "" | tee -a "$LOGFILE"
echo "--- Processing sites ---" | tee -a "$LOGFILE"

for site in "$FORGE_HOME"/*/; do
    # Skip if not a git repo
    [ -d "$site/.git" ] || continue

    name=$(basename "$site")
    echo "" | tee -a "$LOGFILE"
    echo "====== $name ======" | tee -a "$LOGFILE"

    cd "$site"

    # 4a. Show untracked files before cleaning
    untracked=$(git status --short 2>/dev/null | grep "^?" || true)
    if [ -n "$untracked" ]; then
        warn "Untracked files:" | tee -a "$LOGFILE"
        echo "$untracked" | tee -a "$LOGFILE"
    fi

    # 4b. Show modified files
    modified=$(git diff --name-only 2>/dev/null || true)
    if [ -n "$modified" ]; then
        warn "Modified files:" | tee -a "$LOGFILE"
        echo "$modified" | tee -a "$LOGFILE"
    fi

    # 4c. Git reset and clean
    git reset --hard HEAD 2>&1 | tee -a "$LOGFILE"
    git clean -df 2>&1 | tee -a "$LOGFILE"
    log "Git restored" | tee -a "$LOGFILE"

    # 4d. PHP files in storage (excluding compiled views)
    suspect_storage=$(find storage/ -name "*.php" -not -path "*/views/*" 2>/dev/null || true)
    if [ -n "$suspect_storage" ]; then
        echo "$suspect_storage" | while read -r f; do
            fail "Removing suspect: $f" | tee -a "$LOGFILE"
            rm -f "$f"
        done
    fi

    # 4e. PHP files in upload directories
    find public/uploads/ public/files/ public/images/ public/media/ \
        -name "*.php" 2>/dev/null | while read -r f; do
        fail "Removing suspect upload: $f" | tee -a "$LOGFILE"
        rm -f "$f"
    done

    # 4f. Suspect PHP files in public/ that survived git clean
    #     (hex-named files, common webshell names)
    find public/ -maxdepth 2 -name "*.php" 2>/dev/null | while read -r f; do
        base=$(basename "$f")
        # Skip known Laravel files
        case "$base" in
            index.php|robots.txt|.htaccess) continue ;;
        esac
        # Flag hex-named or known webshell names
        if echo "$base" | grep -qE "^[0-9a-f]{8,}\.|^s\.php$|^shell|^cmd|^c99|^r57|^b374k|^wso|^alfa|^mini|^phpinfo"; then
            fail "Removing suspect public file: $f" | tee -a "$LOGFILE"
            rm -f "$f"
        fi
    done

    # 4g. Scan remaining PHP for common webshell signatures (report only)
    hits=$(grep -rl "eval\s*(.*base64_decode\|gzinflate\|str_rot13\|shell_exec\|passthru\|assert\s*(" \
        --include="*.php" public/ app/ routes/ config/ bootstrap/ 2>/dev/null \
        | grep -v vendor || true)
    if [ -n "$hits" ]; then
        warn "Files with suspicious signatures (review manually):" | tee -a "$LOGFILE"
        echo "$hits" | tee -a "$LOGFILE"
    fi

    log "$name done" | tee -a "$LOGFILE"
done

echo "" | tee -a "$LOGFILE"
echo "=== Cleanup complete ===" | tee -a "$LOGFILE"
echo "Log saved to: $LOGFILE"
echo ""
warn "STILL REQUIRED:"
echo "  1. Rotate ALL .env credentials on every site"
echo "  2. php artisan key:generate on every site"
echo "  3. Rotate database passwords"
echo "  4. Check nginx logs for the entry vector"
echo "  5. Consider full server rebuild via Forge"
