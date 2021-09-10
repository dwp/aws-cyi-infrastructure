#!/usr/bin/env bash
set -Eeuo pipefail

(
    # Import the logging functions
    source /opt/emr/logging.sh

    function log_wrapper_message() {
        log_aws_cyi_message "$${1}" "create-cyi-database.sh" "Running as: ,$USER"
    }

    CORRELATION_ID="$2"
    S3_BUCKET="$4"
    S3_PREFIX="$6"
    EXPORT_DATE="$8"

    log_wrapper_message "Correlation id is '$CORRELATION_ID', s3 bucket is '$S3_BUCKET', s3 prefix is '$S3_PREFIX' and export date is '$EXPORT_DATE', "

    echo "$CORRELATION_ID" >>     /opt/emr/correlation_id.txt
    echo "$S3_BUCKET" >>          /opt/emr/s3_bucket.txt
    echo "$S3_PREFIX" >>          /opt/emr/s3_prefix.txt
    echo "$EXPORT_DATE" >>        /opt/emr/export_date.txt

    log_wrapper_message "Creating CYI database"

    hive -e "CREATE DATABASE IF NOT EXISTS ${cyi_db} LOCATION '${published_bucket}/${hive_metastore_location}';"

    log_wrapper_message "Finished creating CYI database"

) >> /var/log/cyi/create_cyi_databases.log 2>&1
