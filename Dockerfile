FROM nextcloud:stable-fpm
MAINTAINER boredazfcuk

# nextcloud_version variable not used. Simply increment to force a full rebuild of the container
ARG nextcloud_version="21.0.1"
ARG app_dependencies="tzdata passwd redis-server mariadb-client procps ffmpeg libfcgi-bin smbclient libsmbclient-dev cifs-utils sssd realmd clamav iproute2 net-tools imagemagick sudo"

RUN echo "$(date '+%c') | ***** BUILD STARTED FOR NEXTCLOUD *****" && \
echo "$(date '+%c') | Install dependencies" && \
   apt-get update && \
   apt-get remove -y imagemagick-6-common && \
   apt-get autoremove -y && \
   apt-get install -y ${app_dependencies} && \
   pecl install smbclient && \
   docker-php-ext-enable smbclient

COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
COPY cron.sh /usr/local/bin/cron.sh

RUN echo "$(date '+%c') | Set execute permissions on scripts" && \
   chmod +x /entrypoint.sh /usr/local/bin/healthcheck.sh /usr/local/bin/cron.sh && \
   apt-get clean && \
   echo "Init" > "/initialise_container" && \
echo "$(date '+%c') | ***** BUILD COMPLETE *****"

HEALTHCHECK --start-period=10s --interval=1m --timeout=10s \
   CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]