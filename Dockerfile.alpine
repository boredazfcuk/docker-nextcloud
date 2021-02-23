FROM nextcloud:stable-fpm-alpine
MAINTAINER boredazfcuk
# nextcloud_version variable not used. Simply increment to force a full rebuild of the container
ARG nextcloud_version="18.0.7"
ARG app_dependencies="shadow tzdata redis php7-pecl-redis mariadb-client fcgi procps ffmpeg"

RUN echo "$(date '+%c') | ***** BUILD STARTED FOR NEXTCLOUD *****" && \
echo "$(date '+%c') | Install dependencies" && \
   apk add --no-cache --no-progress ${app_dependencies}

COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN echo "$(date '+%c') | Set execute permissions on scripts" && \
   chmod +x /entrypoint.sh /usr/local/bin/healthcheck.sh && \
   echo "Init" > "/initialise_container" && \
echo "$(date '+%c') | ***** BUILD COMPLETE *****"

HEALTHCHECK --start-period=10s --interval=1m --timeout=10s \
   CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]