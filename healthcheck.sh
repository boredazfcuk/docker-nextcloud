#!/bin/sh

if [ "$("$(which php)" -v > /dev/null; echo $?)" -ne 0 ]; then
   echo "PHP application not available"
   exit 1
fi

if [ "$("$(which mysql)" --protocol=tcp -h "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "USE ${MYSQL_DATABASE};"; echo $?)" -ne 0 ]; then
   echo "Nextcloud database not available"
   exit 1
fi

echo "PHP and Nextcloud database responding OK"
exit 0