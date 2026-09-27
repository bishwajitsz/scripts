#!/usr/bin/env bash

###############################################################################
# Universal Bare Repository Deployment Runner
#
# Repository:
#   https://github.com/bishwajitsz/scripts
#
# Intended usage:
#
#   ./bare-repo-deploy.sh \
#       --target /home/analysis/htdocs/example.com \
#       --git-dir /home/analysis/repo \
#       --branch main \
#       --all
#
###############################################################################

set -Eeuo pipefail

###############################################################################
# VERSION
###############################################################################

SCRIPT_NAME="bare-repo-deploy"
SCRIPT_VERSION="2.0.0"

###############################################################################
# DEFAULT CONFIGURATION
###############################################################################

TARGET="${DEPLOY_TARGET:-}"
GIT_DIR="${DEPLOY_GIT_DIR:-}"
BRANCH="${DEPLOY_BRANCH:-main}"

PHP_BIN="${PHP_BIN:-/usr/bin/php8.5}"
COMPOSER_BIN="${COMPOSER_BIN:-/usr/local/bin/composer}"
NPM_BIN="${NPM_BIN:-npm}"
NODE_BIN="${NODE_BIN:-node}"
GIT_BIN="${GIT_BIN:-git}"

PACKISTRY_URL="${PACKISTRY_URL:-https://packistry.tradifylabs.com}"

MEMORY_LIMIT="${MEMORY_LIMIT:-512M}"

RUN_AS_USER="${DEPLOY_USER:-}"
RUN_AS_GROUP="${DEPLOY_GROUP:-}"

LOCK_FILE="${DEPLOY_LOCK_FILE:-/tmp/${SCRIPT_NAME}.lock}"

LOG_DIR="${DEPLOY_LOG_DIR:-}"
LOG_FILE=""

HEALTH_URL=""
HEALTH_EXPECTED_STATUS="200"
HEALTH_TIMEOUT="30"

DRY_RUN=false
VERBOSE=false
AUTO_YES=false
FORCE=false

MAINTENANCE=false
MAINTENANCE_RETRY=60

USE_NPM_CI="auto"

###############################################################################
# COMMAND QUEUE
###############################################################################

declare -a COMMANDS=()

###############################################################################
# COLORS
###############################################################################

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    WHITE=''
    NC=''
fi

###############################################################################
# LOGGING
###############################################################################

log() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $*"
    fi
}

section() {
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}$*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

###############################################################################
# ERROR HANDLING
###############################################################################

CURRENT_STEP="initialization"
DEPLOYMENT_STARTED_AT="$(date +%s)"

MAINTENANCE_ENABLED=false

cleanup() {
    local exit_code=$?

    if [[ "$MAINTENANCE_ENABLED" == true ]]; then
        warning "Deployment stopped while maintenance mode is enabled."

        if [[ -f "${TARGET:-}/artisan" ]]; then
            php_artisan up >/dev/null 2>&1 || true
        fi
    fi

    if [[ -n "${LOCK_FD:-}" ]]; then
        flock -u "$LOCK_FD" 2>/dev/null || true
    fi

    return "$exit_code"
}

handle_error() {
    local exit_code=$?

    error "Deployment failed."
    error "Step: ${CURRENT_STEP}"
    error "Exit code: ${exit_code}"

    if [[ -f "${TARGET:-}/artisan" ]]; then
        warning "Attempting Laravel maintenance recovery..."

        if [[ "$DRY_RUN" == false ]]; then
            php_artisan up >/dev/null 2>&1 || true
        fi
    fi

    exit "$exit_code"
}

trap handle_error ERR
trap cleanup EXIT

###############################################################################
# BASIC HELPERS
###############################################################################

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    if ! command_exists "$1"; then
        error "Required command not found: $1"
        exit 127
    fi
}

run() {
    debug "Running: $*"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
        return 0
    fi

    "$@"
}

run_quiet() {
    if [[ "$DRY_RUN" == true ]]; then
        debug "[DRY-RUN] $*"
        return 0
    fi

    "$@" >/dev/null 2>&1
}

confirm() {
    if [[ "$AUTO_YES" == true || "$FORCE" == true ]]; then
        return 0
    fi

    read -r -p "$1 [y/N] " answer

    case "$answer" in
        y|Y|yes|YES|Yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

###############################################################################
# VALIDATION
###############################################################################

validate_target() {
    if [[ -z "$TARGET" ]]; then
        error "--target is required."
        exit 1
    fi

    if [[ ! -d "$TARGET" ]]; then
        error "Target directory does not exist: $TARGET"
        exit 1
    fi
}

validate_git() {
    if [[ -z "$GIT_DIR" ]]; then
        error "--git-dir is required for Git operations."
        exit 1
    fi

    if [[ ! -d "$GIT_DIR" ]]; then
        error "Git directory does not exist: $GIT_DIR"
        exit 1
    fi
}

validate_laravel() {
    if [[ ! -f "$TARGET/artisan" ]]; then
        error "Laravel artisan file not found in: $TARGET"
        exit 1
    fi
}

validate_php() {
    require_command "$PHP_BIN"
}

validate_environment() {
    section "Environment Validation"

    validate_target
    validate_php

    log "Target: $TARGET"
    log "Branch: $BRANCH"
    log "PHP: $PHP_BIN"
    log "Composer: $COMPOSER_BIN"
    log "Node: $NODE_BIN"
    log "NPM: $NPM_BIN"

    success "Environment validated."
}

###############################################################################
# PHP / ARTISAN
###############################################################################

php() {
    "$PHP_BIN" \
        -d "memory_limit=${MEMORY_LIMIT}" \
        "$@"
}

php_artisan() {
    php "$TARGET/artisan" "$@"
}

###############################################################################
# LOCK
###############################################################################

acquire_lock() {
    CURRENT_STEP="Acquire deployment lock"

    section "Deployment Lock"

    require_command flock

    exec {LOCK_FD}>"$LOCK_FILE"

    if ! flock -n "$LOCK_FD"; then
        error "Another deployment is already running."
        error "Lock: $LOCK_FILE"
        exit 1
    fi

    log "Deployment lock acquired."
}

###############################################################################
# LOG FILE
###############################################################################

setup_logging() {
    if [[ -z "$LOG_DIR" ]]; then
        return
    fi

    mkdir -p "$LOG_DIR"

    LOG_FILE="$LOG_DIR/deploy-$(date '+%Y%m%d-%H%M%S').log"

    exec > >(tee -a "$LOG_FILE") 2>&1

    log "Log file: $LOG_FILE"
}

###############################################################################
# GIT
###############################################################################

git_checkout() {
    CURRENT_STEP="Git checkout"

    section "Git Checkout"

    validate_git
    require_command "$GIT_BIN"

    log "Branch: $BRANCH"

    run "$GIT_BIN" \
        --work-tree="$TARGET" \
        --git-dir="$GIT_DIR" \
        checkout -f "$BRANCH"

    success "Git checkout completed."
}

git_fetch() {
    CURRENT_STEP="Git fetch"

    section "Git Fetch"

    validate_git

    run "$GIT_BIN" \
        --git-dir="$GIT_DIR" \
        fetch --all --prune

    success "Git fetch completed."
}

git_status() {
    CURRENT_STEP="Git status"

    section "Git Status"

    cd "$TARGET"

    run "$GIT_BIN" status
}

git_reset() {
    CURRENT_STEP="Git reset"

    section "Git Reset"

    cd "$TARGET"

    if ! confirm "Reset working tree?"; then
        warning "Cancelled."
        return
    fi

    run "$GIT_BIN" reset --hard

    success "Git reset completed."
}

git_clean() {
    CURRENT_STEP="Git clean"

    section "Git Clean"

    cd "$TARGET"

    if ! confirm "Remove untracked files?"; then
        warning "Cancelled."
        return
    fi

    run "$GIT_BIN" clean -fd

    success "Git clean completed."
}

###############################################################################
# PACKISTRY
###############################################################################

configure_packistry() {
    CURRENT_STEP="Configure Packistry"

    section "Packistry"

    local composer_file="$TARGET/composer.json"

    if [[ ! -f "$composer_file" ]]; then
        warning "composer.json not found."
        return
    fi

    php -r '
        $file = $argv[1];
        $packistry = $argv[2];

        $json = file_get_contents($file);

        if ($json === false) {
            throw new RuntimeException("Unable to read composer.json");
        }

        $data = json_decode($json, true);

        if (json_last_error() !== JSON_ERROR_NONE) {
            throw new RuntimeException(
                "Invalid composer.json: " . json_last_error_msg()
            );
        }

        if (!isset($data["repositories"]) || !is_array($data["repositories"])) {
            echo "No repositories section found.\n";
            exit(0);
        }

        $changed = false;

        foreach ($data["repositories"] as $key => $repository) {

            if (
                ($repository["type"] ?? null) === "path" &&
                ($repository["url"] ?? null) === "../../Packages/*"
            ) {
                $data["repositories"][$key] = [
                    "type" => "composer",
                    "url" => $packistry
                ];

                $changed = true;

                echo "Replaced ../../Packages/* with Packistry.\n";
            }
        }

        if (!$changed) {
            echo "No local Packages repository found.\n";
            exit(0);
        }

        $encoded = json_encode(
            $data,
            JSON_PRETTY_PRINT |
            JSON_UNESCAPED_SLASHES |
            JSON_UNESCAPED_UNICODE
        );

        if ($encoded === false) {
            throw new RuntimeException("Unable to encode composer.json");
        }

        file_put_contents($file, $encoded . PHP_EOL);

        echo "composer.json updated successfully.\n";

    ' "$composer_file" "$PACKISTRY_URL"

    success "Packistry configuration completed."
}

###############################################################################
# COMPOSER
###############################################################################

composer_validate() {
    CURRENT_STEP="Composer validate"

    section "Composer Validate"

    cd "$TARGET"

    run "$COMPOSER_BIN" validate

    success "Composer validation completed."
}

composer_install() {
    CURRENT_STEP="Composer install"

    section "Composer Install"

    cd "$TARGET"

    run "$PHP_BIN" "$COMPOSER_BIN" install \
        --no-interaction \
        --prefer-dist \
        --optimize-autoloader \
        --ignore-platform-reqs

    success "Composer install completed."
}

composer_install_prod() {
    CURRENT_STEP="Composer production install"

    section "Composer Production Install"

    cd "$TARGET"

    run "$PHP_BIN" "$COMPOSER_BIN" install \
        --no-interaction \
        --prefer-dist \
        --optimize-autoloader \
        --no-dev \
        --ignore-platform-reqs

    success "Composer production install completed."
}

composer_update() {
    CURRENT_STEP="Composer update"

    section "Composer Update"

    cd "$TARGET"

    if ! confirm "Run composer update?"; then
        warning "Cancelled."
        return
    fi

    run "$PHP_BIN" "$COMPOSER_BIN" update \
        --no-interaction \
        --prefer-dist \
        --ignore-platform-reqs
}

composer_autoload() {
    CURRENT_STEP="Composer autoload"

    section "Composer Autoload"

    cd "$TARGET"

    run "$PHP_BIN" "$COMPOSER_BIN" dump-autoload \
        --optimize \
        --no-interaction
}

composer_clear_cache() {
    CURRENT_STEP="Composer cache"

    section "Composer Cache"

    run "$PHP_BIN" "$COMPOSER_BIN" clear-cache
}

###############################################################################
# NODE
###############################################################################

npm_install() {
    CURRENT_STEP="NPM install"

    section "NPM Install"

    cd "$TARGET"

    if [[ "$USE_NPM_CI" == "auto" && -f package-lock.json ]]; then
        log "package-lock.json found. Using npm ci."
        run "$NPM_BIN" ci
    else
        run "$NPM_BIN" install
    fi

    success "NPM dependencies installed."
}

npm_ci() {
    CURRENT_STEP="NPM CI"

    section "NPM CI"

    cd "$TARGET"

    run "$NPM_BIN" ci

    success "NPM CI completed."
}

npm_update() {
    CURRENT_STEP="NPM update"

    section "NPM Update"

    cd "$TARGET"

    if ! confirm "Run npm update?"; then
        warning "Cancelled."
        return
    fi

    run "$NPM_BIN" update
}

npm_build() {
    CURRENT_STEP="NPM build"

    section "NPM Build"

    cd "$TARGET"

    run "$NPM_BIN" run build

    success "NPM build completed."
}

npm_audit() {
    CURRENT_STEP="NPM audit"

    section "NPM Audit"

    cd "$TARGET"

    run "$NPM_BIN" audit
}

###############################################################################
# MAINTENANCE
###############################################################################

maintenance_down() {
    CURRENT_STEP="Maintenance down"

    section "Maintenance Mode ON"

    validate_laravel

    php_artisan down --retry="$MAINTENANCE_RETRY"

    MAINTENANCE_ENABLED=true

    success "Application is in maintenance mode."
}

maintenance_up() {
    CURRENT_STEP="Maintenance up"

    section "Maintenance Mode OFF"

    validate_laravel

    php_artisan up

    MAINTENANCE_ENABLED=false

    success "Application is online."
}

###############################################################################
# CACHE
###############################################################################

optimize_clear() {
    CURRENT_STEP="Optimize clear"

    section "Laravel Optimize Clear"

    validate_laravel

    php_artisan optimize:clear
}

optimize() {
    CURRENT_STEP="Optimize"

    section "Laravel Optimize"

    validate_laravel

    php_artisan optimize
}

config_cache() {
    CURRENT_STEP="Config cache"

    validate_laravel

    php_artisan config:cache
}

config_clear() {
    CURRENT_STEP="Config clear"

    validate_laravel

    php_artisan config:clear
}

route_cache() {
    CURRENT_STEP="Route cache"

    validate_laravel

    php_artisan route:cache
}

route_clear() {
    CURRENT_STEP="Route clear"

    validate_laravel

    php_artisan route:clear
}

view_cache() {
    CURRENT_STEP="View cache"

    validate_laravel

    php_artisan view:cache
}

view_clear() {
    CURRENT_STEP="View clear"

    validate_laravel

    php_artisan view:clear
}

event_cache() {
    CURRENT_STEP="Event cache"

    validate_laravel

    php_artisan event:cache
}

event_clear() {
    CURRENT_STEP="Event clear"

    validate_laravel

    php_artisan event:clear
}

cache_clear() {
    CURRENT_STEP="Application cache clear"

    validate_laravel

    php_artisan cache:clear
}

###############################################################################
# DATABASE
###############################################################################

migrate() {
    CURRENT_STEP="Database migration"

    section "Database Migration"

    validate_laravel

    php_artisan migrate \
        --force \
        --no-interaction

    success "Migrations completed."
}

migrate_status() {
    CURRENT_STEP="Migration status"

    validate_laravel

    php_artisan migrate:status
}

migrate_rollback() {
    CURRENT_STEP="Migration rollback"

    validate_laravel

    php_artisan migrate:rollback \
        --force \
        --no-interaction
}

migrate_fresh() {
    CURRENT_STEP="Migration fresh"

    section "DANGER: MIGRATE FRESH"

    warning "This will destroy all database tables."

    if ! confirm "Continue?"; then
        return
    fi

    validate_laravel

    php_artisan migrate:fresh \
        --force \
        --no-interaction
}

seed() {
    CURRENT_STEP="Database seed"

    validate_laravel

    php_artisan db:seed \
        --force \
        --no-interaction
}

###############################################################################
# STORAGE
###############################################################################

storage_link() {
    CURRENT_STEP="Storage link"

    validate_laravel

    php_artisan storage:link
}

storage_unlink() {
    CURRENT_STEP="Storage unlink"

    validate_laravel

    php_artisan storage:unlink
}

###############################################################################
# QUEUE
###############################################################################

queue_restart() {
    CURRENT_STEP="Queue restart"

    validate_laravel

    php_artisan queue:restart

    success "Queue restart requested."
}

queue_work() {
    CURRENT_STEP="Queue worker"

    validate_laravel

    php_artisan queue:work
}

queue_flush() {
    CURRENT_STEP="Queue flush"

    warning "This will flush queued jobs."

    if ! confirm "Continue?"; then
        return
    fi

    validate_laravel

    php_artisan queue:flush
}

failed_retry() {
    CURRENT_STEP="Failed jobs retry"

    validate_laravel

    php_artisan queue:retry all
}

failed_flush() {
    CURRENT_STEP="Failed jobs flush"

    warning "This will remove failed jobs."

    if ! confirm "Continue?"; then
        return
    fi

    validate_laravel

    php_artisan queue:flush
}

###############################################################################
# SCHEDULER
###############################################################################

schedule_list() {
    CURRENT_STEP="Schedule list"

    validate_laravel

    php_artisan schedule:list
}

###############################################################################
# HORIZON
###############################################################################

horizon_pause() {
    CURRENT_STEP="Horizon pause"

    validate_laravel

    php_artisan horizon:pause
}

horizon_continue() {
    CURRENT_STEP="Horizon continue"

    validate_laravel

    php_artisan horizon:continue
}

horizon_terminate() {
    CURRENT_STEP="Horizon terminate"

    validate_laravel

    php_artisan horizon:terminate
}

###############################################################################
# STORAGE / PERMISSIONS
###############################################################################

permissions() {
    CURRENT_STEP="Permissions"

    section "Permissions"

    if [[ -z "$RUN_AS_USER" ]]; then
        warning "--user not supplied. Skipping ownership."
        return
    fi

    local group="${RUN_AS_GROUP:-$RUN_AS_USER}"

    run chown -R "${RUN_AS_USER}:${group}" "$TARGET"

    [[ -d "$TARGET/storage" ]] &&
        run chmod -R ug+rwX "$TARGET/storage"

    [[ -d "$TARGET/bootstrap/cache" ]] &&
        run chmod -R ug+rwX "$TARGET/bootstrap/cache"

    success "Permissions updated."
}

###############################################################################
# HEALTH CHECK
###############################################################################

health_check() {
    CURRENT_STEP="Health check"

    section "Health Check"

    validate_laravel

    log "Laravel:"
    php_artisan --version

    log "PHP:"
    php --version | head -n 1

    if command_exists "$NODE_BIN"; then
        log "Node:"
        "$NODE_BIN" --version
    fi

    if command_exists "$NPM_BIN"; then
        log "NPM:"
        "$NPM_BIN" --version
    fi

    if command_exists "$COMPOSER_BIN"; then
        log "Composer:"
        "$PHP_BIN" "$COMPOSER_BIN" --version
    fi

    if [[ -n "$HEALTH_URL" ]]; then
        require_command curl

        log "HTTP health check: $HEALTH_URL"

        local status

        status="$(
            curl \
                --silent \
                --show-error \
                --output /dev/null \
                --write-out '%{http_code}' \
                --max-time "$HEALTH_TIMEOUT" \
                "$HEALTH_URL"
        )"

        if [[ "$status" != "$HEALTH_EXPECTED_STATUS" ]]; then
            error "Health check failed. HTTP $status"
            return 1
        fi

        success "HTTP health check passed."
    fi

    success "Health check completed."
}

###############################################################################
# FULL DEPLOYMENT
###############################################################################

deploy_all() {
    CURRENT_STEP="Full deployment"

    section "FULL DEPLOYMENT"

    log "Target: $TARGET"
    log "Branch: $BRANCH"

    acquire_lock

    maintenance_down

    git_checkout

    cd "$TARGET"

    configure_packistry

    composer_validate
    composer_install

    if [[ -f "$TARGET/package.json" ]]; then
        npm_install
        npm_build
    else
        warning "package.json not found. Skipping Node."
    fi

    optimize_clear

    migrate

    storage_link

    optimize

    queue_restart

    permissions

    health_check

    maintenance_up

    success "FULL DEPLOYMENT COMPLETED."
}

###############################################################################
# PRODUCTION DEPLOYMENT
###############################################################################

deploy_production() {
    CURRENT_STEP="Production deployment"

    section "PRODUCTION DEPLOYMENT"

    acquire_lock

    maintenance_down

    git_checkout

    cd "$TARGET"

    configure_packistry

    composer_validate
    composer_install_prod

    if [[ -f "$TARGET/package-lock.json" ]]; then
        npm_ci
    elif [[ -f "$TARGET/package.json" ]]; then
        npm_install
    fi

    if [[ -f "$TARGET/package.json" ]]; then
        npm_build
    fi

    optimize_clear

    migrate

    storage_link

    optimize

    queue_restart

    permissions

    health_check

    maintenance_up

    success "PRODUCTION DEPLOYMENT COMPLETED."
}

###############################################################################
# INFO
###############################################################################

show_info() {
    section "Deployment Information"

    echo "Script:          $SCRIPT_NAME"
    echo "Version:         $SCRIPT_VERSION"
    echo "Target:          ${TARGET:-<unset>}"
    echo "Git directory:   ${GIT_DIR:-<unset>}"
    echo "Branch:          $BRANCH"
    echo "PHP:             $PHP_BIN"
    echo "Composer:        $COMPOSER_BIN"
    echo "Node:            $NODE_BIN"
    echo "NPM:             $NPM_BIN"
    echo "Git:             $GIT_BIN"
    echo "Packistry:       $PACKISTRY_URL"
    echo "Memory limit:    $MEMORY_LIMIT"
    echo "Dry run:         $DRY_RUN"
    echo "Verbose:         $VERBOSE"
}

###############################################################################
# HELP
###############################################################################

show_help() {
cat <<EOF

$SCRIPT_NAME v$SCRIPT_VERSION

Universal Laravel deployment runner for bare Git repositories.

USAGE

    $SCRIPT_NAME [OPTIONS]

CONFIGURATION

    --target PATH
    --git-dir PATH
    --branch NAME
    --php PATH
    --composer-bin PATH
    --npm-bin PATH
    --node-bin PATH
    --git-bin PATH
    --packistry-url URL
    --memory-limit VALUE
    --user USER
    --group GROUP

GIT

    --checkout
    --fetch
    --status
    --reset
    --clean

COMPOSER

    --packistry
    --composer
    --composer-prod
    --composer-update
    --composer-validate
    --composer-autoload
    --composer-clear-cache

NODE / NPM

    --npm
    --npm-ci
    --npm-update
    --npm-build
    --npm-audit

LARAVEL

    --maintenance-down
    --maintenance-up

    --optimize-clear
    --optimize

    --config-clear
    --config-cache

    --route-clear
    --route-cache

    --view-clear
    --view-cache

    --event-clear
    --event-cache

    --cache-clear

DATABASE

    --migrate
    --migrate-status
    --migrate-rollback
    --migrate-fresh
    --seed

STORAGE

    --storage-link
    --storage-unlink

QUEUE

    --queue-restart
    --queue-work
    --queue-flush
    --failed-retry
    --failed-flush

SCHEDULER

    --schedule-list

HORIZON

    --horizon-pause
    --horizon-continue
    --horizon-terminate

OTHER

    --permissions
    --health
    --info

DEPLOYMENT PRESETS

    --production
    --all

RUNTIME

    --dry-run
    --verbose
    --yes
    --force
    --help

EXAMPLES

    $SCRIPT_NAME \\
        --target /var/www/example.com \\
        --git-dir /var/repositories/example.git \\
        --branch main \\
        --all

    $SCRIPT_NAME \\
        --target /var/www/example.com \\
        --composer \\
        --npm-ci \\
        --npm-build

    $SCRIPT_NAME \\
        --target /var/www/example.com \\
        --packistry \\
        --composer

    $SCRIPT_NAME \\
        --target /var/www/example.com \\
        --migrate \\
        --optimize-clear \\
        --optimize

    $SCRIPT_NAME \\
        --target /var/www/example.com \\
        --all \\
        --dry-run

EOF
}

###############################################################################
# ARGUMENT PARSER
###############################################################################

while [[ $# -gt 0 ]]; do

    case "$1" in

        --target)
            TARGET="${2:?Missing value for --target}"
            shift 2
            ;;

        --git-dir)
            GIT_DIR="${2:?Missing value for --git-dir}"
            shift 2
            ;;

        --branch)
            BRANCH="${2:?Missing value for --branch}"
            shift 2
            ;;

        --php)
            PHP_BIN="${2:?Missing value for --php}"
            shift 2
            ;;

        --composer-bin)
            COMPOSER_BIN="${2:?Missing value for --composer-bin}"
            shift 2
            ;;

        --npm-bin)
            NPM_BIN="${2:?Missing value for --npm-bin}"
            shift 2
            ;;

        --node-bin)
            NODE_BIN="${2:?Missing value for --node-bin}"
            shift 2
            ;;

        --git-bin)
            GIT_BIN="${2:?Missing value for --git-bin}"
            shift 2
            ;;

        --packistry-url)
            PACKISTRY_URL="${2:?Missing value for --packistry-url}"
            shift 2
            ;;

        --memory-limit)
            MEMORY_LIMIT="${2:?Missing value for --memory-limit}"
            shift 2
            ;;

        --user)
            RUN_AS_USER="${2:?Missing value for --user}"
            shift 2
            ;;

        --group)
            RUN_AS_GROUP="${2:?Missing value for --group}"
            shift 2
            ;;

        --health-url)
            HEALTH_URL="${2:?Missing value for --health-url}"
            shift 2
            ;;

        --health-status)
            HEALTH_EXPECTED_STATUS="${2:?Missing value for --health-status}"
            shift 2
            ;;

        --health-timeout)
            HEALTH_TIMEOUT="${2:?Missing value for --health-timeout}"
            shift 2
            ;;

        --log-dir)
            LOG_DIR="${2:?Missing value for --log-dir}"
            shift 2
            ;;

        #######################################################################
        # Git
        #######################################################################

        --checkout)
            COMMANDS+=("checkout")
            shift
            ;;

        --fetch)
            COMMANDS+=("fetch")
            shift
            ;;

        --status)
            COMMANDS+=("status")
            shift
            ;;

        --reset)
            COMMANDS+=("reset")
            shift
            ;;

        --clean)
            COMMANDS+=("clean")
            shift
            ;;

        #######################################################################
        # Composer
        #######################################################################

        --packistry)
            COMMANDS+=("packistry")
            shift
            ;;

        --composer)
            COMMANDS+=("composer")
            shift
            ;;

        --composer-prod)
            COMMANDS+=("composer-prod")
            shift
            ;;

        --composer-update)
            COMMANDS+=("composer-update")
            shift
            ;;

        --composer-validate)
            COMMANDS+=("composer-validate")
            shift
            ;;

        --composer-autoload)
            COMMANDS+=("composer-autoload")
            shift
            ;;

        --composer-clear-cache)
            COMMANDS+=("composer-clear-cache")
            shift
            ;;

        #######################################################################
        # NPM
        #######################################################################

        --npm)
            COMMANDS+=("npm")
            shift
            ;;

        --npm-ci)
            COMMANDS+=("npm-ci")
            shift
            ;;

        --npm-update)
            COMMANDS+=("npm-update")
            shift
            ;;

        --npm-build|--build)
            COMMANDS+=("npm-build")
            shift
            ;;

        --npm-audit)
            COMMANDS+=("npm-audit")
            shift
            ;;

        #######################################################################
        # Laravel
        #######################################################################

        --maintenance-down)
            COMMANDS+=("maintenance-down")
            shift
            ;;

        --maintenance-up)
            COMMANDS+=("maintenance-up")
            shift
            ;;

        --optimize-clear)
            COMMANDS+=("optimize-clear")
            shift
            ;;

        --optimize)
            COMMANDS+=("optimize")
            shift
            ;;

        --config-clear)
            COMMANDS+=("config-clear")
            shift
            ;;

        --config-cache)
            COMMANDS+=("config-cache")
            shift
            ;;

        --route-clear)
            COMMANDS+=("route-clear")
            shift
            ;;

        --route-cache)
            COMMANDS+=("route-cache")
            shift
            ;;

        --view-clear)
            COMMANDS+=("view-clear")
            shift
            ;;

        --view-cache)
            COMMANDS+=("view-cache")
            shift
            ;;

        --event-clear)
            COMMANDS+=("event-clear")
            shift
            ;;

        --event-cache)
            COMMANDS+=("event-cache")
            shift
            ;;

        --cache-clear)
            COMMANDS+=("cache-clear")
            shift
            ;;

        #######################################################################
        # Database
        #######################################################################

        --migrate)
            COMMANDS+=("migrate")
            shift
            ;;

        --migrate-status)
            COMMANDS+=("migrate-status")
            shift
            ;;

        --migrate-rollback)
            COMMANDS+=("migrate-rollback")
            shift
            ;;

        --migrate-fresh)
            COMMANDS+=("migrate-fresh")
            shift
            ;;

        --seed)
            COMMANDS+=("seed")
            shift
            ;;

        #######################################################################
        # Storage
        #######################################################################

        --storage-link)
            COMMANDS+=("storage-link")
            shift
            ;;

        --storage-unlink)
            COMMANDS+=("storage-unlink")
            shift
            ;;

        #######################################################################
        # Queue
        #######################################################################

        --queue-restart)
            COMMANDS+=("queue-restart")
            shift
            ;;

        --queue-work)
            COMMANDS+=("queue-work")
            shift
            ;;

        --queue-flush)
            COMMANDS+=("queue-flush")
            shift
            ;;

        --failed-retry)
            COMMANDS+=("failed-retry")
            shift
            ;;

        --failed-flush)
            COMMANDS+=("failed-flush")
            shift
            ;;

        #######################################################################
        # Scheduler / Horizon
        #######################################################################

        --schedule-list)
            COMMANDS+=("schedule-list")
            shift
            ;;

        --horizon-pause)
            COMMANDS+=("horizon-pause")
            shift
            ;;

        --horizon-continue)
            COMMANDS+=("horizon-continue")
            shift
            ;;

        --horizon-terminate)
            COMMANDS+=("horizon-terminate")
            shift
            ;;

        #######################################################################
        # Misc
        #######################################################################

        --permissions)
            COMMANDS+=("permissions")
            shift
            ;;

        --health)
            COMMANDS+=("health")
            shift
            ;;

        --info)
            COMMANDS+=("info")
            shift
            ;;

        #######################################################################
        # Presets
        #######################################################################

        --production)
            COMMANDS+=("production")
            shift
            ;;

        --all)
            COMMANDS+=("all")
            shift
            ;;

        #######################################################################
        # Runtime
        #######################################################################

        --dry-run)
            DRY_RUN=true
            shift
            ;;

        --verbose)
            VERBOSE=true
            shift
            ;;

        --yes)
            AUTO_YES=true
            shift
            ;;

        --force)
            FORCE=true
            AUTO_YES=true
            shift
            ;;

        --help|-h)
            show_help
            exit 0
            ;;

        --version|-v)
            echo "$SCRIPT_NAME $SCRIPT_VERSION"
            exit 0
            ;;

        *)
            error "Unknown option: $1"
            echo
            show_help
            exit 1
            ;;

    esac

done

###############################################################################
# MAIN
###############################################################################

if [[ ${#COMMANDS[@]} -eq 0 ]]; then
    show_help
    exit 0
fi

validate_environment
setup_logging

###############################################################################
# COMMAND EXECUTION
###############################################################################

for COMMAND in "${COMMANDS[@]}"; do

    case "$COMMAND" in

        checkout)
            git_checkout
            ;;

        fetch)
            git_fetch
            ;;

        status)
            git_status
            ;;

        reset)
            git_reset
            ;;

        clean)
            git_clean
            ;;

        packistry)
            configure_packistry
            ;;

        composer)
            composer_install
            ;;

        composer-prod)
            composer_install_prod
            ;;

        composer-update)
            composer_update
            ;;

        composer-validate)
            composer_validate
            ;;

        composer-autoload)
            composer_autoload
            ;;

        composer-clear-cache)
            composer_clear_cache
            ;;

        npm)
            npm_install
            ;;

        npm-ci)
            npm_ci
            ;;

        npm-update)
            npm_update
            ;;

        npm-build)
            npm_build
            ;;

        npm-audit)
            npm_audit
            ;;

        maintenance-down)
            maintenance_down
            ;;

        maintenance-up)
            maintenance_up
            ;;

        optimize-clear)
            optimize_clear
            ;;

        optimize)
            optimize
            ;;

        config-clear)
            config_clear
            ;;

        config-cache)
            config_cache
            ;;

        route-clear)
            route_clear
            ;;

        route-cache)
            route_cache
            ;;

        view-clear)
            view_clear
            ;;

        view-cache)
            view_cache
            ;;

        event-clear)
            event_clear
            ;;

        event-cache)
            event_cache
            ;;

        cache-clear)
            cache_clear
            ;;

        migrate)
            migrate
            ;;

        migrate-status)
            migrate_status
            ;;

        migrate-rollback)
            migrate_rollback
            ;;

        migrate-fresh)
            migrate_fresh
            ;;

        seed)
            seed
            ;;

        storage-link)
            storage_link
            ;;

        storage-unlink)
            storage_unlink
            ;;

        queue-restart)
            queue_restart
            ;;

        queue-work)
            queue_work
            ;;

        queue-flush)
            queue_flush
            ;;

        failed-retry)
            failed_retry
            ;;

        failed-flush)
            failed_flush
            ;;

        schedule-list)
            schedule_list
            ;;

        horizon-pause)
            horizon_pause
            ;;

        horizon-continue)
            horizon_continue
            ;;

        horizon-terminate)
            horizon_terminate
            ;;

        permissions)
            permissions
            ;;

        health)
            health_check
            ;;

        info)
            show_info
            ;;

        production)
            deploy_production
            ;;

        all)
            deploy_all
            ;;

        *)
            error "Unknown internal command: $COMMAND"
            exit 1
            ;;

    esac

done

###############################################################################
# FINISH
###############################################################################

DURATION=$(( $(date +%s) - DEPLOYMENT_STARTED_AT ))

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Deployment completed successfully.${NC}"
echo -e "${GREEN}  Duration: ${DURATION}s${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
