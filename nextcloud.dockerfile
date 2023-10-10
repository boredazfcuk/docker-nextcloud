FROM nextcloud:stable

MAINTAINER boredazfcuk

# nextcloud_version variable not used. Simply increment to force a full rebuild of the container
ARG nextcloud_version="27.0.2"
ARG app_dependencies="tzdata mariadb-client ffmpeg"

RUN echo "$(date '+%c') | ***** BUILD STARTED FOR NEXTCLOUD *****" && \
   mkdir --parents /nextcloud_data /usr/src/nextcloud/core/skeleton_empty /var/www/html/nextcloud && \
   chown 33:33 /nextcloud_data /usr/src/nextcloud/core/skeleton_empty /var/www/html/nextcloud && \
echo "$(date '+%c') | Install dependencies" && \
   apt-get update && \
   apt-get install -y ${app_dependencies} && \
echo "$(date '+%c') | Cleanup and exit" && \
   rm -rf /var/lib/apt/lists/* && \
   apt-get clean && \
   sed -i -e "s%/var/www/html/$%/var/www/html/nextcloud/%g" \
      -e "s%/var/www/html/\$dir%/var/www/html/nextcloud/\$dir%g" \
      -e "s%/var/www/html/occ%/var/www/html/nextcloud/occ%g" \
      -e "s%/var/www/html/version.php%/var/www/html/nextcloud/version.php%g" \
      -e "s%/var/www/html/nextcloud-init-sync.lock%/var/www/html/nextcloud/nextcloud-init-sync.lock%g" \
      /entrypoint.sh && \
echo "$(date '+%c') | ***** BUILD COMPLETE *****"

COPY --chmod=0755 cron_launcher.sh /docker-entrypoint-hooks.d/before-starting/
COPY --chmod=0755 cron.sh /usr/local/bin/cron.sh
COPY --chmod=0755 healthcheck.sh /usr/local/bin/healthcheck.sh

HEALTHCHECK --start-period=1m --interval=1m --timeout=10s  CMD /usr/local/bin/healthcheck.sh