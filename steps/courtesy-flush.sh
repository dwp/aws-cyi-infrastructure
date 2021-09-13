#!/bin/bash


CORRELATION_ID="$2"
S3_BUCKET="$4"
S3_PREFIX="$6"
EXPORT_DATE="$8"

(
    # Import the logging functions
    source /opt/emr/logging.sh

    function log_wrapper_message() {
        log_cyi_message "$${1}" "courtesy-flush.sh" "Running as: ,$USER"
    }

    # Set the ddb values as this is the initial step
    log_wrapper_message "Correlation id is '$CORRELATION_ID', s3 bucket is '$S3_BUCKET', s3 prefix is '$S3_PREFIX' and export date is '$EXPORT_DATE', "

    echo "$CORRELATION_ID" >>     /opt/emr/correlation_id.txt
    echo "$S3_BUCKET" >>          /opt/emr/s3_bucket.txt
    echo "$S3_PREFIX" >>          /opt/emr/s3_prefix.txt
    echo "$EXPORT_DATE" >>        /opt/emr/export_date.txt

    log_wrapper_message "Flushing the CYI pushgateway"
    curl -X PUT "http://${cyi_pushgateway_hostname}:9091/api/v1/admin/wipe"
    log_wrapper_message "Done flushing the CYI pushgateway"

) >> /var/log/cyi/courtesy_flush.log 2>&1
