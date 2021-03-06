#!/usr/bin/env bash
set -Eeuo pipefail

CORRELATION_ID="$2"
S3_BUCKET="$4"
S3_PREFIX="$6"
EXPORT_DATE="$8"
START_DATE="$${10:-NOT_SET}"

#CYI operates on previous days prefix, however the export date is todays date for all clusters
#Therefore the export date is manipulated to be the previous date
DAY_BEFORE_EXPORT_DATE=$(date -d "$EXPORT_DATE -1 days" +"%Y-%m-%d")

(
  source /opt/emr/logging.sh

  function log_wrapper_message() {
      log_cyi_message "$${1}" "run-cyi.sh" "Running as: ,$USER"
  }

  log_wrapper_message "Executing temp table creation and merge for correlation id '$CORRELATION_ID', s3 bucket '$S3_BUCKET', s3 prefix '$S3_PREFIX', export date '$EXPORT_DATE', day_before_export date '$DAY_BEFORE_EXPORT_DATE' and start date '$START_DATE'"

  if [[ "$START_DATE" == "NOT_SET" ]]; then
    python3 /var/ci/generate_external_table.py --correlation_id "$CORRELATION_ID" --export_date "$DAY_BEFORE_EXPORT_DATE"
  else
    python3 /var/ci/generate_external_table.py --correlation_id "$CORRELATION_ID" --export_date "$DAY_BEFORE_EXPORT_DATE" --start_date "$START_DATE"
  fi

) >> /var/log/cyi/run_cyi.log 2>&1
