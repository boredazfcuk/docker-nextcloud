#!/bin/ash

#####Functions #####
Initialise(){
   echo "$(date '+%Y-%m-%d %H:%M:%S') INFO:    ***** Starting Nextcloud container *****"

   if [ -z "${USER}" ]; then echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User name not set, defaulting to 'nextcloud'"; USER="nextcloud"; fi
   if [ -z "${UID}" ]; then echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User ID not set, defaulting to '1000'"; UID="1000"; fi
   if [ -z "${GROUP}" ]; then echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Group name not set, defaulting to 'www-data'"; GROUP="www-data"; fi
   if [ -z "${GID}" ]; then echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Group ID not set, defaulting to '1000'"; GID="1000"; fi

   echo "$(date '+%Y-%m-%d %H:%M:%S') INFO:    Local user: ${USER}:${UID}"
   echo "$(date '+%Y-%m-%d %H:%M:%S') INFO:    Local group: ${GROUP}:${GID}"
}

ConfigureServices(){

   echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set PHP config options"
   sed -i -e 's#^doc_root =*#doc_root = /var/www/html#' \
      -e 's#^memory_limit =.*#memory_limit = 256M#' \
      -e 's#^output_buffering =.*#output_buffering = Off#' \
      -e 's#^max_execution_time =.*#max_execution_time = 1800#' \
      -e 's#^max_input_time =.*#max_input_time = 3600#' \
      -e 's#^post_max_size =.*#post_max_size = 40960M#' \
      -e 's#^upload_max_filesize =.*#upload_max_filesize = 40960M#' \
      -e 's#^max_file_uploads =.*#max_file_uploads = 100#' \
      -e 's#^;date.timezone.*#date.timezone = Europe/London#' \
      -e 's#^;opcache.enable=.*#opcache.enable=1#' \
      -e 's#^;opcache.enable_cli=.*#opcache.enable_cli=1#' \
      -e 's#^;opcache.memory_consumption=.*#opcache.memory_consumption=128#' \
      -e 's#^;opcache.interned_strings_buffer=.*#opcache.interned_strings_buffer=8#' \
      -e 's#^;opcache.max_accelerated_files=.*#opcache.max_accelerated_files=10000#' \
      -e 's#^;opcache.revalidate_freq=.*#opcache.revalidate_freq=1#' \
      -e 's#^;opcache.save_comments=.*#opcache.save_comments=1#' \
      -e 's#^;session.cookie_secure.*#session.cookie_secure = True#' \
      /usr/local/etc/php/php.ini

   echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set PHP pool options"
   sed -i -e 's#^user =.*#user = www-data#' \
      -e 's#^group =.*#group = www-data#' \
      -e 's#^listen =.*#listen = $HOSTNAME:9000#' \
      -e 's#^;access.log =.*#access.log = /dev/stderr#' \
      -e 's#^;env[HOSTNAME] = $HOSTNAME#env[HOSTNAME] = $HOSTNAME#' \
      -e 's#^;env[PATH] = /usr/local/bin:/usr/bin:/bin#env[PATH] = /usr/local/bin:/usr/bin:/bin#' \
      -e 's#^;env[TMP] = /tmp#env[TMP] = /tmp#' \
      -e 's#^;env[TMPDIR] = /tmp#env[TMPDIR] = /tmp#' \
      -e 's#^;env[TEMP] = /tmp#env[TEMP] = /tmp#' \
      -e 's#^pm.max_children =.*#pm.max_children = 240#' \
      -e 's#^pm.start_servers =.*#pm.start_servers = 6#' \
      -e 's#^pm.min_spare_servers =.*#pm.min_spare_servers = 3#' \
      -e 's#^pm.max_spare_servers =.*#pm.max_spare_servers = 9#' \
      -e 's#^;pm.max_requests =.*#pm.max_requests = 250#' \
      -e 's#^;pm.status_path =.*#pm.status_path = /status#' \
      /usr/local/etc/php-fpm.d/www.conf
   
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set PHP-FPM options"
   sed -i -e 's#;error_log =.*#error_log = /dev/stderr#' \
      -e 's#;log_level =.*#log_level = notice#' \
      -e 's#;daemonize =.*#daemonize = no#' \
      -e 's#;emergency_restart_threshold =.*#emergency_restart_threshold = 10#' \
      -e 's#;emergency_restart_interval =.*#emergency_restart_interval = 1m#' \
      -e 's#;process_control_timeout =.*#process_control_timeout = 10s#' \
      /usr/local/etc/php-fpm.conf
   
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set Redis options"
   sed -i -e 's#^logfile /var/log/.*#logfile /dev/stdout#' /etc/redis.conf
}

ChangeGroup(){
   if [ ! -z "${GID}" ] && [ -z "$(getent group "${GID}" | cut -d: -f3)" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') INFO:    Group ID available, changing group ID for www-data"
      groupmod -o www-data -g "${GID}"
   elif [ ! "$(getent group "${GROUP}" | cut -d: -f3)" = "${GID}" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR:   Group GID in use, cannot continue"
      exit 1
   fi
}

ChangeUser(){
   if [ ! -z "${UID}" ] && [ ! -z "${GID}" ] && [ -z "$(getent passwd "${USER}" | cut -d: -f3)" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') INFO:    User ID available, changing user and primary group"
      usermod -o www-data -u "${UID}" -g "${GID}"
   elif [ ! "$(getent passwd "${USER}" | cut -d: -f3)" = "${UID}" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR:   User ID already in use - exiting"
      exit 1
   fi
}

##### Script #####
Initialise
ChangeGroup
ChangeUser