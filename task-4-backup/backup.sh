#!/usr/bin/env bash
# =============================================================================
# backup.sh — MySQL database backup with S3 upload
#
# Usage:
#   chmod +x backup.sh
#   ./backup.sh
#
# Required environment variables (no hard-coded credentials):
#   MYSQL_HOST       — MySQL server hostname or IP  (default: localhost)
#   MYSQL_PORT       — MySQL port                   (default: 3306)
#   MYSQL_DATABASE   — Database name to back up     (REQUIRED)
#   MYSQL_USER       — MySQL user                   (REQUIRED)
#   MYSQL_PASSWORD   — MySQL password               (REQUIRED — use a secrets manager or IAM auth in prod)
#   S3_BUCKET        — S3 bucket name               (REQUIRED)
#   AWS_REGION       — AWS region                   (default: us-east-1)
#   BACKUP_DIR       — Local staging directory      (default: /tmp/db_backups)
#
# Authentication:
#   AWS credentials are NOT hard-coded. The script relies on the EC2 Instance
#   IAM Role attached to the server (or a configured AWS CLI profile).
#   Ensure the IAM Role has the following permissions on the target bucket:
#     s3:PutObject, s3:GetObject, s3:ListBucket, s3:DeleteObject
# =============================================================================

set -euo pipefail

# ─── Logging helpers ─────────────────────────────────────────────────────────
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

log_info()  { echo "${LOG_PREFIX} [INFO]  $*"; }
log_warn()  { echo "${LOG_PREFIX} [WARN]  $*" >&2; }
log_error() { echo "${LOG_PREFIX} [ERROR] $*" >&2; }

# ─── Configuration (from environment variables) ───────────────────────────────
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_DATABASE="${MYSQL_DATABASE:-}"
MYSQL_USER="${MYSQL_USER:-}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
S3_BUCKET="${S3_BUCKET:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/db_backups}"

# ─── Validate required variables ──────────────────────────────────────────────
validate_config() {
    local missing=0
    for var in MYSQL_DATABASE MYSQL_USER MYSQL_PASSWORD S3_BUCKET; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable '${var}' is not set."
            missing=1
        fi
    done
    if [[ "${missing}" -eq 1 ]]; then
        log_error "One or more required variables are missing. Aborting."
        exit 1
    fi
}

# ─── Verify required tools are installed ──────────────────────────────────────
check_dependencies() {
    local deps=("mysqldump" "gzip" "aws")
    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            log_error "Required tool '${dep}' is not installed or not in PATH."
            exit 1
        fi
    done
    log_info "All required dependencies found."
}

# ─── Create local staging directory ───────────────────────────────────────────
prepare_backup_dir() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        mkdir -p "${BACKUP_DIR}"
        log_info "Created backup staging directory: ${BACKUP_DIR}"
    fi
}

# ─── Take MySQL backup ─────────────────────────────────────────────────────────
perform_backup() {
    TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
    BACKUP_FILENAME="${MYSQL_DATABASE}_${TIMESTAMP}.sql.gz"
    BACKUP_FILEPATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

    log_info "Starting backup of database '${MYSQL_DATABASE}' from '${MYSQL_HOST}:${MYSQL_PORT}'..."

    # mysqldump piped directly into gzip — avoids storing uncompressed SQL on disk
    if mysqldump \
        --host="${MYSQL_HOST}" \
        --port="${MYSQL_PORT}" \
        --user="${MYSQL_USER}" \
        --password="${MYSQL_PASSWORD}" \
        --single-transaction \
        --routines \
        --triggers \
        --set-gtid-purged=OFF \
        "${MYSQL_DATABASE}" | gzip -9 > "${BACKUP_FILEPATH}"; then
        log_info "Backup created successfully: ${BACKUP_FILEPATH}"
    else
        log_error "mysqldump failed for database '${MYSQL_DATABASE}'."
        # Clean up partial file
        rm -f "${BACKUP_FILEPATH}"
        exit 1
    fi

    # Verify the compressed file is non-empty
    if [[ ! -s "${BACKUP_FILEPATH}" ]]; then
        log_error "Backup file is empty: ${BACKUP_FILEPATH}"
        rm -f "${BACKUP_FILEPATH}"
        exit 1
    fi

    BACKUP_SIZE=$(du -sh "${BACKUP_FILEPATH}" | cut -f1)
    log_info "Backup file size: ${BACKUP_SIZE}"
}

# ─── Upload backup to S3 ───────────────────────────────────────────────────────
upload_to_s3() {
    S3_KEY="mysql-backups/${MYSQL_DATABASE}/${BACKUP_FILENAME}"
    S3_URI="s3://${S3_BUCKET}/${S3_KEY}"

    log_info "Uploading '${BACKUP_FILEPATH}' to '${S3_URI}'..."

    if aws s3 cp "${BACKUP_FILEPATH}" "${S3_URI}" \
        --region "${AWS_REGION}" \
        --storage-class STANDARD_IA \
        --no-progress; then
        log_info "Upload successful: ${S3_URI}"
    else
        log_error "S3 upload failed for '${BACKUP_FILEPATH}'."
        exit 1
    fi
}

# ─── Clean up local staging file ──────────────────────────────────────────────
cleanup_local() {
    rm -f "${BACKUP_FILEPATH}"
    log_info "Removed local staging file: ${BACKUP_FILEPATH}"
}

# ─── Script-based retention: delete backups older than 7 days from S3 ─────────
# NOTE: The preferred approach for retention is an S3 Lifecycle Policy
# (see retention-approach.md). This function is provided as a fallback
# for environments where Lifecycle Policies cannot be configured.
enforce_retention_script() {
    local RETENTION_DAYS=7
    local CUTOFF_DATE
    CUTOFF_DATE=$(date -d "-${RETENTION_DAYS} days" '+%Y-%m-%d' 2>/dev/null \
        || date -v "-${RETENTION_DAYS}d" '+%Y-%m-%d')   # macOS fallback

    log_info "Checking for backups older than ${RETENTION_DAYS} days (before ${CUTOFF_DATE})..."

    # List objects in the backup prefix, filter by LastModified < cutoff, delete them
    aws s3api list-objects-v2 \
        --bucket "${S3_BUCKET}" \
        --prefix "mysql-backups/${MYSQL_DATABASE}/" \
        --region "${AWS_REGION}" \
        --query "Contents[?LastModified<='${CUTOFF_DATE}'].Key" \
        --output text | tr '\t' '\n' | while IFS= read -r key; do
            if [[ -n "${key}" && "${key}" != "None" ]]; then
                log_info "Deleting expired backup: s3://${S3_BUCKET}/${key}"
                aws s3 rm "s3://${S3_BUCKET}/${key}" --region "${AWS_REGION}"
            fi
        done

    log_info "Retention enforcement complete."
}

# ─── Main ──────────────────────────────────────────────────────────────────────
main() {
    log_info "========================================================"
    log_info "MySQL Backup Script started"
    log_info "========================================================"

    validate_config
    check_dependencies
    prepare_backup_dir
    perform_backup
    upload_to_s3
    cleanup_local
    enforce_retention_script

    log_info "========================================================"
    log_info "Backup completed successfully: ${BACKUP_FILENAME}"
    log_info "========================================================"
}

main "$@"
