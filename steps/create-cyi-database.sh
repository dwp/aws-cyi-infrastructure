#!/usr/bin/env bash
set -Eeuo pipefail

(
    # Import the logging functions
    source /opt/emr/logging.sh

    function log_wrapper_message() {
        log_cyi_message "$${1}" "create-cyi-database.sh" "Running as: ,$USER"
    }

    log_wrapper_message "Creating CYI database"

    hive -e "CREATE DATABASE IF NOT EXISTS ${cyi_db} LOCATION '${published_bucket}/${hive_metastore_location}';"

    log_wrapper_message "Finished creating CYI database"

) >> /var/log/cyi/create_cyi_databases.log 2>&1
