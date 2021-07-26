#!/bin/bash

sleep 30

while :; do
   echo "Running cron script..."
   sudo --user www-data --preserve-env "$(which php)" -f "${NEXTCLOUD_INSTALL_DIR}/cron.php"
   echo "Execution of cron script complete"
   sleep 300
done
