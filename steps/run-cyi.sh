#!/usr/bin/env bash

source /opt/emr/logging.sh

function log_wrapper_message() {
    log_cyi_message "$${1}" "run-cyi.sh" "Running as: ,$USER"
}

CORRELATION_ID=$(cat /opt/emr/correlation_id.txt)
EXPORT_DATE=$(cat /opt/emr/export_date.txt)

(
  log_wrapper_message "Executing temp table creation and merge for export date ${EXPORT_DATE}"

  python3 generate_external_table.py --correlation_id $CORRELATION_ID --export_date $EXPORT_DATE
) >> /var/log/cyi/run_cyi.log 2>&1
