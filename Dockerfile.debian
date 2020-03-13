#FROM nextcloud:stable-fpm-alpine
FROM nextcloud:17.0.3-fpm
MAINTAINER boredazfcuk

RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD STARTED *****" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install dependencies" && \
   apt-get update && \
   apt-get install -y tzdata passwd redis-server mariadb-client smbclient
# php-redis php-fpm

COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set execute permissions on scripts" && \
   chmod +x /entrypoint.sh /usr/local/bin/healthcheck.sh && \
   apt-get clean && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD COMPLETE *****"

HEALTHCHECK --start-period=10s --interval=1m --timeout=10s \
   CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]