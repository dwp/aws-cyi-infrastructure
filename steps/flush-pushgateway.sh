#!/bin/bash

# This script waits for a fixed period to give the metrics scraper enough
# time to collect CYI's metrics. It then deletes all of CYI's metrics so that
# the scraper doesn't continually gather stale metrics long past CYI's termination.

(
    # Import the logging functions
    source /opt/emr/logging.sh

    function log_wrapper_message() {
        log_cyi_message "$${1}" "flush-pushgateway.sh" "Running as: ,$USER"
    }

    log_wrapper_message "Sleeping for 3m"

    sleep 180 # scrape interval is 60, scrape timeout is 10, 5 for the pot

    log_wrapper_message "Flushing the CYI  pushgateway"
    curl -X PUT "http://${cyi_pushgateway_hostname}:9091/api/v1/admin/wipe"
    log_wrapper_message "Done flushing the CYI pushgateway"

) >> /var/log/cyi/flush_pushgateway.log 2>&1
