#!/usr/bin/env bash

###############################################################################
# Universal Laravel Deployment Script
#
# Usage:
#
#   curl -fsSL https://gist.githubusercontent.com/USER/GIST_ID/raw/deploy.sh \
#       | bash -s -- --target /path/to/project --all
#
# Examples:
#
#   ./deploy.sh --all
#
#   ./deploy.sh \
#       --target /home/analysis/htdocs/example.com \
#       --git-dir /home/analysis/repo \
#       --branch main \
#       --composer \
#       --npm \
#       --build \
#       --optimize
#
###############################################################################

set -Eeuo pipefail

###############################################################################
# Defaults
###############################################################################

TARGET="${DEPLOY_TARGET:-$(pwd)}"
GIT_DIR="${DEPLOY_GIT_DIR:-}"
BRANCH="${DEPLOY_BRANCH:-main}"

PHP_BIN="${PHP_BIN:-php}"
COMPOSER_BIN="${COMPOSER_BIN:-composer}"
NPM_BIN="${NPM_BIN:-npm}"
NODE_BIN="${NODE_BIN:-node}"
GIT_BIN="${GIT_BIN:-git}"

PACKISTRY_URL="${PACKISTRY_URL:-https://packistry.tradifylabs.com}"

MEMORY_LIMIT="${MEMORY_LIMIT:-512M}"

RUN_AS_USER=""
RUN_AS_GROUP=""

DRY_RUN=false
VERBOSE=false
FORCE=false
AUTO_YES=false

###############################################################################
# Colors
###############################################################################

if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly MAGENTA='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly MAGENTA=''
    readonly CYAN=''
    readonly WHITE=''
    readonly NC=''
fi

###############################################################################
# Logging
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
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}$*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

###############################################################################
# Error handling
###############################################################################

CURRENT_STEP="initialization"

handle_error() {
    local exit_code=$?

    error "Deployment failed."
    error "Step: ${CURRENT_STEP}"
    error "Exit code: ${exit_code}"

    if [[ -f "$TARGET/artisan" ]]; then
        warning "Attempting to bring Laravel application back online..."

        if [[ "$DRY_RUN" == false ]]; then
            php_artisan up >/dev/null 2>&1 || true
        fi
    fi

    exit "$exit_code"
}

trap handle_error ERR

###############################################################################
# Helpers
###############################################################################

run() {
    debug "Running: $*"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
        return 0
    fi

    "$@"
}

run_shell() {
    debug "Running shell: $*"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
        return 0
    fi

    bash -c "$*"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    if ! command_exists "$1"; then
        error "Required command not found: $1"
        exit 127
    fi
}

confirm() {
    if [[ "$AUTO_YES" == true ]]; then
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
# PHP / Artisan helpers
###############################################################################

php() {
    "$PHP_BIN" -d "memory_limit=${MEMORY_LIMIT}" "$@"
}

php_artisan() {
    php "$TARGET/artisan" "$@"
}

###############################################################################
# Git
###############################################################################

git_checkout() {
    CURRENT_STEP="Git checkout"

    section "Git Checkout"

    [[ -n "$GIT_DIR" ]] || {
        error "--git-dir is required for Git checkout."
        exit 1
    }

    require_command "$GIT_BIN"

    log "Checking out branch: $BRANCH"

    run "$GIT_BIN" \
        --work-tree="$TARGET" \
        --git-dir="$GIT_DIR" \
        checkout -f "$BRANCH"

    success "Git checkout completed."
}

git_pull() {
    CURRENT_STEP="Git pull"

    section "Git Pull"

    require_command "$GIT_BIN"

    cd "$TARGET"

    run "$GIT_BIN" pull --ff-only

    success "Git pull completed."
}

git_fetch() {
    CURRENT_STEP="Git fetch"

    section "Git Fetch"

    require_command "$GIT_BIN"

    if [[ -n "$GIT_DIR" ]]; then
        run "$GIT_BIN" \
            --git-dir="$GIT_DIR" \
            fetch --all --prune
    else
        cd "$TARGET"
        run "$GIT_BIN" fetch --all --prune
    fi

    success "Git fetch completed."
}

git_reset() {
    CURRENT_STEP="Git reset"

    section "Git Reset"

    require_command "$GIT_BIN"

    cd "$TARGET"

    warning "This will reset the working tree."

    if ! confirm "Continue?"; then
        warning "Git reset cancelled."
        return
    fi

    run "$GIT_BIN" reset --hard

    success "Git reset completed."
}

git_clean() {
    CURRENT_STEP="Git clean"

    section "Git Clean"

    require_command "$GIT_BIN"

    cd "$TARGET"

    warning "This will remove untracked files."

    if ! confirm "Continue?"; then
        warning "Git clean cancelled."
        return
    fi

    run "$GIT_BIN" clean -fd

    success "Git clean completed."
}

git_status() {
    CURRENT_STEP="Git status"

    section "Git Status"

    require_command "$GIT_BIN"

    cd "$TARGET"

    run "$GIT_BIN" status
}

###############################################################################
# Composer
###############################################################################

configure_packistry() {
    CURRENT_STEP="Configure Packistry"

    section "Configure Packistry"

    local composer_file="$TARGET/composer.json"

    if [[ ! -f "$composer_file" ]]; then
        warning "composer.json not found."
        return 0
    fi

    log "Checking composer repositories..."

    php -r '
        $file = $argv[1];
        $packistry = $argv[2];

        $json = file_get_contents($file);

        if ($json === false) {
            fwrite(STDERR, "Unable to read composer.json\n");
            exit(1);
        }

        $data = json_decode($json, true);

        if (json_last_error() !== JSON_ERROR_NONE) {
            fwrite(
                STDERR,
                "Invalid composer.json: " . json_last_error_msg() . PHP_EOL
            );
            exit(1);
        }

        if (
            !isset($data["repositories"]) ||
            !is_array($data["repositories"])
        ) {
            echo "No repositories section found.\n";
            exit(0);
        }

        $changed = false;

        foreach ($data["repositories"] as $key => $repository) {

            if (
                isset($repository["type"], $repository["url"]) &&
                $repository["type"] === "path" &&
                $repository["url"] === "../../Packages/*"
            ) {
                echo "Replacing ../../Packages/* with Packistry...\n";

                $data["repositories"][$key] = [
                    "type" => "composer",
                    "url" => $packistry
                ];

                $changed = true;
            }
        }

        if ($changed) {

            $result = json_encode(
                $data,
                JSON_PRETTY_PRINT |
                JSON_UNESCAPED_SLASHES |
                JSON_UNESCAPED_UNICODE
            );

            if ($result === false) {
                fwrite(STDERR, "Unable to encode composer.json\n");
                exit(1);
            }

            file_put_contents(
                $file,
                $result . PHP_EOL
            );

            echo "Packistry configuration updated.\n";

        } else {

            echo "No ../../Packages/* repository found.\n";
        }

    ' "$composer_file" "$PACKISTRY_URL"

    success "Packistry configuration checked."
}

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

composer_install_production() {
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

    warning "Composer update modifies composer.lock."

    run "$PHP_BIN" "$COMPOSER_BIN" update \
        --no-interaction \
        --prefer-dist \
        --ignore-platform-reqs

    success "Composer update completed."
}

composer_dump_autoload() {
    CURRENT_STEP="Composer dump autoload"

    section "Composer Dump Autoload"

    cd "$TARGET"

    run "$PHP_BIN" "$COMPOSER_BIN" dump-autoload \
        --optimize \
        --no-interaction

    success "Composer autoload generated."
}

composer_clear_cache() {
    CURRENT_STEP="Composer clear cache"

    section "Composer Clear Cache"

    run "$PHP_BIN" "$COMPOSER_BIN" clear-cache

    success "Composer cache cleared."
}

composer_about() {
    CURRENT_STEP="Composer about"

    section "Composer Information"

    run "$PHP_BIN" "$COMPOSER_BIN" about
}

###############################################################################
# NPM / Node
###############################################################################

node_version() {
    CURRENT_STEP="Node version"

    section "Node Version"

    require_command "$NODE_BIN"

    run "$NODE_BIN" --version
    run "$NPM_BIN" --version
}

npm_install() {
    CURRENT_STEP="NPM install"

    section "NPM Install"

    cd "$TARGET"

    run "$NPM_BIN" install

    success "NPM install completed."
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

    run "$NPM_BIN" update

    success "NPM update completed."
}

npm_audit() {
    CURRENT_STEP="NPM audit"

    section "NPM Audit"

    cd "$TARGET"

    run "$NPM_BIN" audit
}

npm_outdated() {
    CURRENT_STEP="NPM outdated"

    section "NPM Outdated"

    cd "$TARGET"

    run "$NPM_BIN" outdated
}

npm_build() {
    CURRENT_STEP="NPM build"

    section "NPM Build"

    cd "$TARGET"

    run "$NPM_BIN" run build

    success "NPM build completed."
}

npm_dev() {
    CURRENT_STEP="NPM dev"

    section "NPM Dev"

    cd "$TARGET"

    run "$NPM_BIN" run dev
}

###############################################################################
# Laravel Maintenance
###############################################################################

maintenance_down() {
    CURRENT_STEP="Laravel maintenance down"

    section "Maintenance Mode: ON"

    php_artisan down \
        --retry=60

    success "Application is now in maintenance mode."
}

maintenance_up() {
    CURRENT_STEP="Laravel maintenance up"

    section "Maintenance Mode: OFF"

    php_artisan up

    success "Application is online."
}

###############################################################################
# Laravel Cache
###############################################################################

artisan_optimize_clear() {
    CURRENT_STEP="Laravel optimize clear"

    section "Laravel Optimize Clear"

    php_artisan optimize:clear

    success "Laravel optimization caches cleared."
}

artisan_optimize() {
    CURRENT_STEP="Laravel optimize"

    section "Laravel Optimize"

    php_artisan optimize

    success "Laravel optimization completed."
}

config_clear() {
    CURRENT_STEP="Config clear"

    section "Config Clear"

    php_artisan config:clear
}

config_cache() {
    CURRENT_STEP="Config cache"

    section "Config Cache"

    php_artisan config:cache
}

route_clear() {
    CURRENT_STEP="Route clear"

    section "Route Clear"

    php_artisan route:clear
}

route_cache() {
    CURRENT_STEP="Route cache"

    section "Route Cache"

    php_artisan route:cache
}

view_clear() {
    CURRENT_STEP="View clear"

    section "View Clear"

    php_artisan view:clear
}

view_cache() {
    CURRENT_STEP="View cache"

    section "View Cache"

    php_artisan view:cache
}

event_clear() {
    CURRENT_STEP="Event clear"

    section "Event Clear"

    php_artisan event:clear
}

event_cache() {
    CURRENT_STEP="Event cache"

    section "Event Cache"

    php_artisan event:cache
}

cache_clear() {
    CURRENT_STEP="Application cache clear"

    section "Application Cache Clear"

    php_artisan cache:clear
}

###############################################################################
# Laravel Database
###############################################################################

migrate() {
    CURRENT_STEP="Database migration"

    section "Database Migration"

    php_artisan migrate \
        --force \
        --no-interaction

    success "Database migrations completed."
}

migrate_fresh() {
    CURRENT_STEP="Database migrate fresh"

    section "Database Migrate Fresh"

    warning "WARNING: migrate:fresh destroys all database tables."

    if ! confirm "Are you absolutely sure?"; then
        warning "Migration cancelled."
        return
    fi

    php_artisan migrate:fresh \
        --force \
        --no-interaction

    success "Database recreated."
}

migrate_rollback() {
    CURRENT_STEP="Database rollback"

    section "Database Rollback"

    php_artisan migrate:rollback \
        --force \
        --no-interaction
}

migrate_status() {
    CURRENT_STEP="Migration status"

    section "Migration Status"

    php_artisan migrate:status
}

db_seed() {
    CURRENT_STEP="Database seed"

    section "Database Seed"

    php_artisan db:seed \
        --force \
        --no-interaction

    success "Database seeding completed."
}

###############################################################################
# Laravel Storage
###############################################################################

storage_link() {
    CURRENT_STEP="Storage link"

    section "Storage Link"

    php_artisan storage:link

    success "Storage link created."
}

storage_unlink() {
    CURRENT_STEP="Storage unlink"

    section "Storage Unlink"

    php_artisan storage:unlink

    success "Storage link removed."
}

###############################################################################
# Queue
###############################################################################

queue_restart() {
    CURRENT_STEP="Queue restart"

    section "Queue Restart"

    php_artisan queue:restart

    success "Queue restart signal sent."
}

queue_work() {
    CURRENT_STEP="Queue worker"

    section "Queue Worker"

    php_artisan queue:work
}

queue_flush() {
    CURRENT_STEP="Queue flush"

    section "Queue Flush"

    warning "This removes all jobs from the queue."

    if ! confirm "Continue?"; then
        return
    fi

    php_artisan queue:flush
}

failed_jobs_retry() {
    CURRENT_STEP="Failed jobs retry"

    section "Retry Failed Jobs"

    php_artisan queue:retry all
}

failed_jobs_flush() {
    CURRENT_STEP="Failed jobs flush"

    section "Flush Failed Jobs"

    warning "This permanently removes failed jobs."

    if ! confirm "Continue?"; then
        return
    fi

    php_artisan queue:flush
}

###############################################################################
# Laravel Scheduler
###############################################################################

schedule_list() {
    CURRENT_STEP="Schedule list"

    section "Laravel Schedule"

    php_artisan schedule:list
}

###############################################################################
# Laravel Horizon
###############################################################################

horizon_pause() {
    CURRENT_STEP="Horizon pause"

    section "Horizon Pause"

    php_artisan horizon:pause
}

horizon_continue() {
    CURRENT_STEP="Horizon continue"

    section "Horizon Continue"

    php_artisan horizon:continue
}

horizon_terminate() {
    CURRENT_STEP="Horizon terminate"

    section "Horizon Terminate"

    php_artisan horizon:terminate
}

###############################################################################
# Laravel Passport / Sanctum / common package commands
###############################################################################

passport_install() {
    CURRENT_STEP="Passport install"

    section "Passport Install"

    php_artisan passport:install
}

passport_keys() {
    CURRENT_STEP="Passport keys"

    section "Passport Keys"

    php_artisan passport:keys
}

###############################################################################
# Permissions
###############################################################################

permissions() {
    CURRENT_STEP="Permissions"

    section "Permissions"

    if [[ -z "$RUN_AS_USER" ]]; then
        warning "No --user supplied. Skipping ownership changes."
        return
    fi

    local group="${RUN_AS_GROUP:-$RUN_AS_USER}"

    log "Setting ownership to ${RUN_AS_USER}:${group}"

    run chown -R "${RUN_AS_USER}:${group}" "$TARGET"

    if [[ -d "$TARGET/storage" ]]; then
        run chmod -R ug+rwX "$TARGET/storage"
    fi

    if [[ -d "$TARGET/bootstrap/cache" ]]; then
        run chmod -R ug+rwX "$TARGET/bootstrap/cache"
    fi

    success "Permissions updated."
}

###############################################################################
# Laravel package publishing
###############################################################################

vendor_publish() {
    CURRENT_STEP="Vendor publish"

    section "Vendor Publish"

    php_artisan vendor:publish \
        --all \
        --force
}

###############################################################################
# Application health checks
###############################################################################

health_check() {
    CURRENT_STEP="Health check"

    section "Application Health Check"

    if [[ ! -f "$TARGET/artisan" ]]; then
        warning "Laravel artisan file not found."
        return
    fi

    log "Laravel version:"
    php_artisan --version

    log "PHP version:"
    php --version | head -n 1

    if command_exists "$NODE_BIN"; then
        log "Node version:"
        "$NODE_BIN" --version
    fi

    if command_exists "$NPM_BIN"; then
        log "NPM version:"
        "$NPM_BIN" --version
    fi

    if command_exists "$COMPOSER_BIN"; then
        log "Composer version:"
        "$PHP_BIN" "$COMPOSER_BIN" --version
    fi

    success "Health check completed."
}

###############################################################################
# Laravel maintenance cleanup
###############################################################################

clear_everything() {
    CURRENT_STEP="Clear all Laravel caches"

    section "Clear Everything"

    php_artisan optimize:clear
    php_artisan cache:clear

    success "Laravel caches cleared."
}

###############################################################################
# Full deployment
###############################################################################

deploy_all() {
    CURRENT_STEP="Full deployment"

    section "FULL DEPLOYMENT"

    log "Target: $TARGET"
    log "Branch: $BRANCH"

    if [[ -n "$GIT_DIR" ]]; then
        log "Git directory: $GIT_DIR"
    fi

    echo

    ###########################################################################
    # Git
    ###########################################################################

    if [[ -n "$GIT_DIR" ]]; then
        git_checkout
    fi

    cd "$TARGET"

    ###########################################################################
    # Packistry
    ###########################################################################

    configure_packistry

    ###########################################################################
    # Composer
    ###########################################################################

    composer_validate
    composer_install

    ###########################################################################
    # NPM
    ###########################################################################

    if [[ -f "$TARGET/package.json" ]]; then
        npm_install
        npm_build
    else
        warning "package.json not found. Skipping NPM."
    fi

    ###########################################################################
    # Laravel
    ###########################################################################

    artisan_optimize_clear

    migrate

    storage_link

    artisan_optimize

    queue_restart

    health_check

    success "FULL DEPLOYMENT COMPLETED."
}

###############################################################################
# Fast production deployment
###############################################################################

deploy_production() {
    CURRENT_STEP="Production deployment"

    section "PRODUCTION DEPLOYMENT"

    if [[ -n "$GIT_DIR" ]]; then
        git_checkout
    fi

    cd "$TARGET"

    configure_packistry

    composer_install_production

    if [[ -f "$TARGET/package-lock.json" ]]; then
        npm_ci
    elif [[ -f "$TARGET/package.json" ]]; then
        npm_install
    fi

    if [[ -f "$TARGET/package.json" ]]; then
        npm_build
    fi

    artisan_optimize_clear

    migrate

    storage_link

    artisan_optimize

    queue_restart

    health_check

    success "PRODUCTION DEPLOYMENT COMPLETED."
}

###############################################################################
# Custom Artisan command
###############################################################################

run_artisan_command() {
    local command="$1"
    shift || true

    CURRENT_STEP="Custom Artisan command"

    section "Artisan: $command"

    php_artisan "$command" "$@"
}

###############################################################################
# Custom shell command
###############################################################################

run_command() {
    CURRENT_STEP="Custom command"

    section "Custom Command"

    run_shell "$*"
}

###############################################################################
# Environment information
###############################################################################

show_info() {
    section "Deployment Environment"

    echo "Target:          $TARGET"
    echo "Git directory:   ${GIT_DIR:-<not configured>}"
    echo "Branch:          $BRANCH"
    echo "PHP:             $PHP_BIN"
    echo "Composer:        $COMPOSER_BIN"
    echo "Node:             $NODE_BIN"
    echo "NPM:              $NPM_BIN"
    echo "Git:              $GIT_BIN"
    echo "Packistry:       $PACKISTRY_URL"
    echo "Memory limit:    $MEMORY_LIMIT"
    echo "Dry run:         $DRY_RUN"
    echo "Verbose:         $VERBOSE"
    echo "Run as user:     ${RUN_AS_USER:-<unchanged>}"
}

###############################################################################
# Help
###############################################################################

show_help() {
cat <<'EOF'

Universal Laravel Deployment Script
====================================

USAGE:

  deploy.sh [OPTIONS] [COMMANDS]


CONFIGURATION
-------------

  --target PATH
      Laravel application directory.

  --git-dir PATH
      Git repository directory.

  --branch NAME
      Git branch to deploy.

  --php PATH
      PHP executable.

  --composer PATH
      Composer executable.

  --npm PATH
      NPM executable.

  --node PATH
      Node executable.

  --git PATH
      Git executable.

  --packistry URL
      Packistry Composer repository.

  --memory-limit VALUE
      PHP memory limit. Default: 512M.

  --user USER
      User for permission changes.

  --group GROUP
      Group for permission changes.


GIT
---

  --checkout
      Checkout configured branch into target.

  --pull
      Git pull --ff-only.

  --fetch
      Git fetch --all --prune.

  --reset
      Git reset --hard.

  --clean
      Git clean -fd.

  --git-status
      Show Git status.


COMPOSER
--------

  --packistry
      Replace ../../Packages/* path repository
      with the configured Packistry repository.

  --composer
      Composer install.

  --composer-prod
      Composer production install with --no-dev.

  --composer-update
      Composer update.

  --composer-validate
      Validate composer.json.

  --composer-autoload
      Dump optimized Composer autoload.

  --composer-clear-cache
      Clear Composer cache.

  --composer-about
      Show Composer information.


NODE / NPM
----------

  --node-version
      Show Node and NPM versions.

  --npm
      npm install.

  --npm-ci
      npm ci.

  --npm-update
      npm update.

  --npm-audit
      npm audit.

  --npm-outdated
      npm outdated.

  --build
      npm run build.

  --dev
      npm run dev.


LARAVEL MAINTENANCE
-------------------

  --maintenance-down
      Enable Laravel maintenance mode.

  --maintenance-up
      Disable Laravel maintenance mode.


LARAVEL CACHE
-------------

  --optimize-clear
      php artisan optimize:clear.

  --optimize
      php artisan optimize.

  --config-clear
      Clear config cache.

  --config-cache
      Cache configuration.

  --route-clear
      Clear route cache.

  --route-cache
      Cache routes.

  --view-clear
      Clear compiled views.

  --view-cache
      Cache views.

  --event-clear
      Clear event cache.

  --event-cache
      Cache events.

  --cache-clear
      Clear application cache.

  --clear
      Clear Laravel caches.


DATABASE
--------

  --migrate
      Run database migrations.

  --migrate-status
      Show migration status.

  --migrate-rollback
      Roll back latest migrations.

  --migrate-fresh
      DROP ALL TABLES and recreate database.

  --seed
      Run database seeders.


STORAGE
-------

  --storage-link
      Create Laravel storage symlink.

  --storage-unlink
      Remove Laravel storage symlink.


QUEUE
-----

  --queue-restart
      Restart Laravel queue workers.

  --queue-work
      Start queue worker.

  --queue-flush
      Flush queue.

  --failed-retry
      Retry failed jobs.

  --failed-flush
      Flush failed jobs.


SCHEDULER
---------

  --schedule-list
      Show Laravel scheduled tasks.


HORIZON
-------

  --horizon-pause
      Pause Horizon.

  --horizon-continue
      Continue Horizon.

  --horizon-terminate
      Terminate Horizon workers.


PASSPORT
--------

  --passport-install
      Install Passport.

  --passport-keys
      Generate Passport keys.


OTHER
-----

  --vendor-publish
      Publish all vendor resources.

  --permissions
      Fix storage/bootstrap permissions.

  --health
      Run deployment health check.

  --info
      Show deployment environment.

  --artisan COMMAND [ARGS...]
      Run an arbitrary Artisan command.

  --command "COMMAND"
      Run an arbitrary shell command.


DEPLOYMENT PRESETS
------------------

  --production
      Production deployment:

        checkout
        packistry
        composer --no-dev
        npm install/ci
        npm build
        optimize:clear
        migrate
        storage:link
        optimize
        queue:restart
        health check


  --all
      Full deployment with standard production workflow.


EXECUTION OPTIONS
-----------------

  --dry-run
      Show what would be executed without executing commands.

  --verbose
      Show detailed execution information.

  --yes
      Automatically answer yes to confirmation prompts.

  --force
      Force dangerous operations where applicable.

  --help
      Show this help.


EXAMPLES
--------

Basic deployment:

  ./deploy.sh --target /var/www/site --all


Git deployment:

  ./deploy.sh \
      --target /var/www/site \
      --git-dir /var/repositories/site \
      --branch main \
      --checkout


Composer only:

  ./deploy.sh \
      --target /var/www/site \
      --packistry \
      --composer


Build frontend:

  ./deploy.sh \
      --target /var/www/site \
      --npm-ci \
      --build


Laravel:

  ./deploy.sh \
      --target /var/www/site \
      --optimize-clear \
      --migrate \
      --storage-link \
      --optimize


Full production deployment:

  ./deploy.sh \
      --target /var/www/site \
      --git-dir /var/repositories/site \
      --branch main \
      --production


Dry run:

  ./deploy.sh \
      --target /var/www/site \
      --all \
      --dry-run


Custom Artisan command:

  ./deploy.sh \
      --target /var/www/site \
      --artisan "queue:restart"


Custom shell command:

  ./deploy.sh \
      --target /var/www/site \
      --command "php artisan about"


EOF
}

###############################################################################
# Argument parsing
###############################################################################

COMMANDS=()

while [[ $# -gt 0 ]]; do

    case "$1" in

        #######################################################################
        # Configuration
        #######################################################################

        --target)
            TARGET="$2"
            shift 2
            ;;

        --git-dir)
            GIT_DIR="$2"
            shift 2
            ;;

        --branch)
            BRANCH="$2"
            shift 2
            ;;

        --php)
            PHP_BIN="$2"
            shift 2
            ;;

        --composer)
            COMMANDS+=("composer")
            shift
            ;;

        --composer-bin)
            COMPOSER_BIN="$2"
            shift 2
            ;;

        --npm-bin)
            NPM_BIN="$2"
            shift 2
            ;;

        --node)
            NODE_BIN="$2"
            shift 2
            ;;

        --git-bin)
            GIT_BIN="$2"
            shift 2
            ;;

        --packistry-url)
            PACKISTRY_URL="$2"
            shift 2
            ;;

        --memory-limit)
            MEMORY_LIMIT="$2"
            shift 2
            ;;

        --user)
            RUN_AS_USER="$2"
            shift 2
            ;;

        --group)
            RUN_AS_GROUP="$2"
            shift 2
            ;;

        #######################################################################
        # Git
        #######################################################################

        --checkout)
            COMMANDS+=("checkout")
            shift
            ;;

        --pull)
            COMMANDS+=("pull")
            shift
            ;;

        --fetch)
            COMMANDS+=("fetch")
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

        --git-status)
            COMMANDS+=("git-status")
            shift
            ;;

        #######################################################################
        # Composer
        #######################################################################

        --packistry)
            COMMANDS+=("packistry")
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

        --composer-about)
            COMMANDS+=("composer-about")
            shift
            ;;

        #######################################################################
        # NPM
        #######################################################################

        --node-version)
            COMMANDS+=("node-version")
            shift
            ;;

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

        --npm-audit)
            COMMANDS+=("npm-audit")
            shift
            ;;

        --npm-outdated)
            COMMANDS+=("npm-outdated")
            shift
            ;;

        --build)
            COMMANDS+=("build")
            shift
            ;;

        --dev)
            COMMANDS+=("dev")
            shift
            ;;

        #######################################################################
        # Maintenance
        #######################################################################

        --maintenance-down)
            COMMANDS+=("maintenance-down")
            shift
            ;;

        --maintenance-up)
            COMMANDS+=("maintenance-up")
            shift
            ;;

        #######################################################################
        # Cache
        #######################################################################

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

        --clear)
            COMMANDS+=("clear")
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
        # Scheduler
        #######################################################################

        --schedule-list)
            COMMANDS+=("schedule-list")
            shift
            ;;

        #######################################################################
        # Horizon
        #######################################################################

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
        # Passport
        #######################################################################

        --passport-install)
            COMMANDS+=("passport-install")
            shift
            ;;

        --passport-keys)
            COMMANDS+=("passport-keys")
            shift
            ;;

        #######################################################################
        # Misc
        #######################################################################

        --vendor-publish)
            COMMANDS+=("vendor-publish")
            shift
            ;;

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
        # Custom
        #######################################################################

        --artisan)
            [[ $# -ge 2 ]] || {
                error "--artisan requires a command."
                exit 1
            }

            run_artisan_command "$2" "${@:3}"

            exit $?
            ;;

        --command)
            [[ $# -ge 2 ]] || {
                error "--command requires a command."
                exit 1
            }

            run_command "$2"

            exit $?
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

        *)
            error "Unknown option: $1"
            echo
            echo "Run with --help for available options."
            exit 1
            ;;

    esac

done

###############################################################################
# Validate
###############################################################################

if [[ ${#COMMANDS[@]} -eq 0 ]]; then
    show_help
    exit 0
fi

if [[ ! -d "$TARGET" ]]; then
    error "Target directory does not exist: $TARGET"
    exit 1
fi

if [[ "$DRY_RUN" == false ]]; then
    require_command "$PHP_BIN"
fi

###############################################################################
# Execute commands in requested order
###############################################################################

for COMMAND in "${COMMANDS[@]}"; do

    case "$COMMAND" in

        #######################################################################
        # Git
        #######################################################################

        checkout)
            git_checkout
            ;;

        pull)
            git_pull
            ;;

        fetch)
            git_fetch
            ;;

        reset)
            git_reset
            ;;

        clean)
            git_clean
            ;;

        git-status)
            git_status
            ;;

        #######################################################################
        # Composer
        #######################################################################

        packistry)
            configure_packistry
            ;;

        composer)
            composer_install
            ;;

        composer-prod)
            composer_install_production
            ;;

        composer-update)
            composer_update
            ;;

        composer-validate)
            composer_validate
            ;;

        composer-autoload)
            composer_dump_autoload
            ;;

        composer-clear-cache)
            composer_clear_cache
            ;;

        composer-about)
            composer_about
            ;;

        #######################################################################
        # NPM
        #######################################################################

        node-version)
            node_version
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

        npm-audit)
            npm_audit
            ;;

        npm-outdated)
            npm_outdated
            ;;

        build)
            npm_build
            ;;

        dev)
            npm_dev
            ;;

        #######################################################################
        # Maintenance
        #######################################################################

        maintenance-down)
            maintenance_down
            ;;

        maintenance-up)
            maintenance_up
            ;;

        #######################################################################
        # Cache
        #######################################################################

        optimize-clear)
            artisan_optimize_clear
            ;;

        optimize)
            artisan_optimize
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

        clear)
            clear_everything
            ;;

        #######################################################################
        # Database
        #######################################################################

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
            db_seed
            ;;

        #######################################################################
        # Storage
        #######################################################################

        storage-link)
            storage_link
            ;;

        storage-unlink)
            storage_unlink
            ;;

        #######################################################################
        # Queue
        #######################################################################

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
            failed_jobs_retry
            ;;

        failed-flush)
            failed_jobs_flush
            ;;

        #######################################################################
        # Scheduler
        #######################################################################

        schedule-list)
            schedule_list
            ;;

        #######################################################################
        # Horizon
        #######################################################################

        horizon-pause)
            horizon_pause
            ;;

        horizon-continue)
            horizon_continue
            ;;

        horizon-terminate)
            horizon_terminate
            ;;

        #######################################################################
        # Passport
        #######################################################################

        passport-install)
            passport_install
            ;;

        passport-keys)
            passport_keys
            ;;

        #######################################################################
        # Misc
        #######################################################################

        vendor-publish)
            vendor_publish
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

        #######################################################################
        # Presets
        #######################################################################

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
# Finished
###############################################################################

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Deployment commands completed successfully.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
