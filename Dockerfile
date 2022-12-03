#FROM nextcloud:21.0.9-fpm
#FROM nextcloud:22.2.7-fpm
FROM nextcloud:stable-fpm

MAINTAINER boredazfcuk

# nextcloud_version variable not used. Simply increment to force a full rebuild of the container
ARG nextcloud_version="24.0.6"
ARG app_dependencies="tzdata passwd redis-server mariadb-client procps ffmpeg libfcgi-bin smbclient libsmbclient-dev cifs-utils sssd realmd clamav clamav-daemon iproute2 net-tools imagemagick sudo supervisor"

RUN echo "$(date '+%c') | ***** BUILD STARTED FOR NEXTCLOUD *****" && \
echo "$(date '+%c') | Install dependencies" && \
   apt-get update && \
   apt-get install -y ${app_dependencies} && \
   pecl install smbclient && \
   docker-php-ext-enable smbclient && \
echo "$(date '+%c') | Set execute permissions on scripts" && \
   mkdir -p /var/log/supervisord /var/run/supervisord /var/run/clamav && \
   chown clamav /var/run/clamav && \
   rm -rf /var/lib/apt/lists/* && \
   apt-get clean && \
   echo "Init" > "/initialise_container" && \
echo "$(date '+%c') | ***** BUILD COMPLETE *****"

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
COPY --chmod=0755 healthcheck.sh /usr/local/bin/healthcheck.sh
COPY supervisord.conf /etc/supervisord.conf

HEALTHCHECK --start-period=1m --interval=1m --timeout=10s  CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
