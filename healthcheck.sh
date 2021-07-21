#!/bin/sh

if [ "$("$(which php)" -v > /dev/null; echo $?)" -ne 0 ]; then
   echo "PHP application not available"
   exit 1
fi

if [ "$(netstat -lnt | grep "^tcp" | awk '{print $4}' | grep -v "^127.0.0.11" | grep -c ":9001")" -ne 1 ]; then
   echo "FastCGI server not listening on port 9001"
   exit 1
fi

if [ "$("$(which mysql)" --protocol=tcp -h "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "USE ${MYSQL_DATABASE};"; echo $?)" -ne 0 ]; then
   echo "Nextcloud database not available"
   exit 1
fi

echo "PHP, FastCGI and Nextcloud database responding OK"
exit 0