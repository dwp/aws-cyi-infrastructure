#!/bin/bash

(
    # Import the logging functions
    source /opt/emr/logging.sh

    function log_wrapper_message() {
        log_cyi_message "$${1}" "installer.sh" "$${PID}" "$${@:2}" "Running as: ,$USER"
    }

    log_wrapper_message "Setting up the HTTP, NO_PROXY & HTTPS Proxy"

    FULL_PROXY="${full_proxy}"
    FULL_NO_PROXY="${full_no_proxy}"
    export http_proxy="$FULL_PROXY"
    export HTTP_PROXY="$FULL_PROXY"
    export https_proxy="$FULL_PROXY"
    export HTTPS_PROXY="$FULL_PROXY"
    export no_proxy="$FULL_NO_PROXY"
    export NO_PROXY="$FULL_NO_PROXY"

    log_wrapper_message "Installing boto3 packages"
    PIP=/usr/bin/pip3

    if [ ! -x $PIP ]; then
    # EMR <= 5.29.0 doesn't install a /usr/bin/pip3 wrapper
      PIP=/usr/bin/pip-3.6
    fi

    sudo -E $PIP install boto3
    sudo -E $PIP install logging
    sudo -E $PIP install findspark

    #shellcheck disable=SC2024
    {
        sudo yum install -y python3-devel
        sudo -E $PIP install pycrypto
        sudo -E $PIP install pycryptodome
        sudo yum remove -y python3-devel
    }

    log_wrapper_message "Completed the installer.sh step of the EMR Cluster"

) >> /var/log/cyi/installer.log 2>&1
