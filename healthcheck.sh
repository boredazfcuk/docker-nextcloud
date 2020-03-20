#!/bin/sh

if [ "$("$(which php)" -v > /dev/null; echo $?)" -ne 0 ]; then
   echo "PHP application not available"
   exit 1
fi

SCRIPT_NAME="/status"
SCRIPT_FILENAME="/usr/local/php/php/fpm/status.html"
REQUEST_METHOD="GET"
if [ "$("$(which cgi-fcgi)" -bind -connect "${HOSTNAME}:9000" >/dev/null; echo $?)" -ne 0 ]; then
   echo "FastCGI server not responding"
   exit 1
fi

if [ "$("$(which mysql)" --protocol=tcp -h "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "USE ${MYSQL_DATABASE};"; echo $?)" -ne 0 ]; then
   echo "Nextcloud database not available"
   exit 1
fi

echo "PHP, FastCGI and Nextcloud database responding OK"
exit 0