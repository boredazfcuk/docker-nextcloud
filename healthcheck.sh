#!/bin/ash

php -v > /dev/null || exit 1
/usr/bin/mysql --protocol=tcp -h $(grep dbhost /var/www/html/$(if [ ! -z "${NEXTCLOUD_BASE_DIR}" ]; then echo "${NEXTCLOUD_BASE_DIR}/"; fi)config/config.php | cut -d"'" -f4) -u $(grep dbuser /var/www/html/$(if [ ! -z "${NEXTCLOUD_BASE_DIR}" ]; then echo "${NEXTCLOUD_BASE_DIR}/"; fi)config/config.php | cut -d"'" -f4) -p$(grep dbpassword /var/www/html/$(if [ ! -z "${NEXTCLOUD_BASE_DIR}" ]; then echo "${NEXTCLOUD_BASE_DIR}/"; fi)config/config.php | cut -d"'" -f4) -e "USE $(grep dbname /var/www/html/$(if [ ! -z "${NEXTCLOUD_BASE_DIR}" ]; then echo "${NEXTCLOUD_BASE_DIR}/"; fi)config/config.php | cut -d"'" -f4);" || exit 1
SCRIPT_NAME=/status; SCRIPT_FILENAME=/usr/local/php/php/fpm/status.html; REQUEST_METHOD=GET; cgi-fcgi -bind -connect "${HOSTNAME}:9000" >/dev/null || exit 1
redis-cli PING >/dev/null || exit 1