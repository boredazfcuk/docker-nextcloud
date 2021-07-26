#!/bin/bash

sleep 30

while :; do
   echo "Starting cron script..."
   sudo -u www-data PHP_VERSION=7.4.21 PHP_MEMORY_LIMIT=512M "$(which php)" -f "${NEXTCLOUD_INSTALL_DIR}/cron.php"
   echo "Execution of cron script complete"
   sleep 300
done
