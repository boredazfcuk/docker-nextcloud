#!/bin/bash

run_as() {
   if [ "$(id -u)" = 0 ]; then
      su -p www-data -s /bin/sh -c "$1"
   else
      sh -c "$1"
   fi
}

echo "Cron jobs running as $(whoami)"

sleep 30

while :; do
   echo -n "Running cron jobs... "
   run_as "/usr/local/bin/php -f ${NEXTCLOUD_INSTALL_DIR}/cron.php"
   echo "complete"
   sleep 300
done
