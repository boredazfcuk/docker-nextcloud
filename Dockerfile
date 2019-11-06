FROM nextcloud:stable-fpm-alpine
MAINTAINER boredazfcuk
ENV NEXTCLOUD_BASE_DIR="nextcloud"

COPY start-nextcloud.sh /usr/local/bin/start-nextcloud.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD STARTED *****" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install dependencies and create required directories" && \
   apk add --no-cache --no-progress shadow && \
   mkdir -p /usr/local/tmp/apc && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install application dependencies" && \
   apk add --no-cache --no-progress nano tzdata redis php7-pecl-redis mariadb-client fcgi && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Change Nextcloud base directory" && \
   if [ ! -z "${NEXTCLOUD_BASE_DIR}" ]; then sed -i -e "s#/var/www/html#/var/www/html/${NEXTCLOUD_BASE_DIR}#g" /entrypoint.sh; fi && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Backup PHP config files" && \
   cp /usr/local/etc/php-fpm.d/www.conf /usr/local/etc/php-fpm.d/www.conf.default && \
   cp /usr/local/etc/php-fpm.conf /usr/local/etc/php-fpm.conf.default && \
   cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini && \
   cp /usr/local/etc/php/php.ini /usr/local/etc/php/php.ini.default && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Add crontab" && \
   if [ ! -z "${NEXTCLOUD_BASE_DIR}" ]; then echo "*/15 * * * * php -f /var/www/html/${NEXTCLOUD_BASE_DIR}cron.php" > "/var/spool/cron/crontabs/www-data"; fi && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set execute permissions on scripts" && \
   chmod +x /usr/local/bin/start-nextcloud.sh /usr/local/bin/healthcheck.sh && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD COMPLETE *****"

HEALTHCHECK --start-period=10s --interval=1m --timeout=10s \
   CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD /usr/local/bin/start-nextcloud.sh && redis-server /etc/redis.conf --daemonize yes && php-fpm