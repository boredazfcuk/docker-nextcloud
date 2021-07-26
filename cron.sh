#!/bin/bash

sleep 30

nextcloud_web_root="${nextcloud_web_root:=/}"
NEXTCLOUD_INSTALL_DIR="/var/www/html${nextcloud_web_root}"

echo "Starting cron script and passing environment variables:"
echo " - NEXTCLOUD_INSTALL_DIR= ${NEXTCLOUD_INSTALL_DIR}"
echo " - PHP_INI_DIR=${PHP_INI_DIR}"
echo " - PHP_EXTRA_CONFIGURE_ARGS=${PHP_EXTRA_CONFIGURE_ARGS}"
echo " - PHP_CFLAGS=${PHP_CFLAGS}"
echo " - PHP_CPPFLAGS=${PHP_CPPFLAGS}"
echo " - PHP_LDFLAGS=${PHP_LDFLAGS}"
echo " - PHP_VERSION=${PHP_VERSION}"
echo " - PHP_URL=${PHP_URL}"
echo " - PHP_ASC_URL=${PHP_ASC_URL}"
echo " - PHP_SHA256=${PHP_SHA256}"
echo " - PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT}"
echo " - PHP_UPLOAD_LIMIT=${PHP_UPLOAD_LIMIT}"
echo " - Launch Command:"
echo sudo -u www-data PHP_INI_DIR="${PHP_INI_DIR}" \
                 PHP_EXTRA_CONFIGURE_ARGS="${PHP_EXTRA_CONFIGURE_ARGS}" \
                 PHP_CFLAGS="${PHP_CFLAGS}" \
                 PHP_CPPFLAGS="${PHP_CPPFLAGS}" \
                 PHP_LDFLAGS="${PHP_LDFLAGS}" \
                 PHP_VERSION="${PHP_VERSION}" \
                 PHP_URL="${PHP_URL}" \
                 PHP_ASC_URL="${PHP_ASC_URL}" \
                 PHP_SHA256="${PHP_SHA256}" \
                 PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT}" \
                 PHP_UPLOAD_LIMIT="${PHP_UPLOAD_LIMIT}" \
                 "$(which php)" -f "${NEXTCLOUD_INSTALL_DIR}/cron.php"

while :; do
   echo "Running cron script..."
   sudo -u www-data PHP_INI_DIR="${PHP_INI_DIR}" \
                    PHP_EXTRA_CONFIGURE_ARGS="${PHP_EXTRA_CONFIGURE_ARGS}" \
                    PHP_CFLAGS="${PHP_CFLAGS}" \
                    PHP_CPPFLAGS="${PHP_CPPFLAGS}" \
                    PHP_LDFLAGS="${PHP_LDFLAGS}" \
                    PHP_VERSION="${PHP_VERSION}" \
                    PHP_URL="${PHP_URL}" \
                    PHP_ASC_URL="${PHP_ASC_URL}" \
                    PHP_SHA256="${PHP_SHA256}" \
                    PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT}" \
                    PHP_UPLOAD_LIMIT="${PHP_UPLOAD_LIMIT}" \
                    "$(which php)" -f "${NEXTCLOUD_INSTALL_DIR}/cron.php"
   echo "Execution of cron script complete"
   sleep 300
done
