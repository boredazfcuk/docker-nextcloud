#!/bin/sh

# version_greater A B returns whether A > B
version_greater() {
   [ "$(printf '%s\n' "$@" | sort -t '.' -n -k1,1 -k2,2 -k3,3 -k4,4 | head -n 1)" != "$1" ]
}

# return true if specified directory is empty
directory_empty() {
   [ -z "$(ls -A "$1/")" ]
}

run_as() {
   if [ "$(id -u)" = 0 ]; then
      su -p www-data -s /bin/sh -c "$1"
   else
      sh -c "$1"
   fi
}

WaitForDBServer(){
   echo
   echo "***** Starting Nextcloud container *****"
   echo "$(cat /etc/*-release | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g' | sed 's/"//g')"
   if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
      echo "MYSQL_ROOT_PASSWORD variable not set, exiting"
      exit 1
   fi
   db_server_online="$(mysql --host="${MYSQL_HOST:=mariadb}" --user=root --password="${MYSQL_ROOT_PASSWORD}" --execute="SELECT 1;" 2>/dev/null | grep -c "1")"
   while [ "${db_server_online}" = 0 ]; do
      echo "Waiting for database server, ${MYSQL_HOST}, to come online..." 
      sleep 10
      db_server_online="$(mysql --host="${MYSQL_HOST}" --user=root --password="${MYSQL_ROOT_PASSWORD}" --execute="SELECT 1;" 2>/dev/null | grep -c "1")" 
   done
}

Initialise(){
   lan_ip="$(hostname -i)"
   echo "Local user: ${user:=nextcloud}:${user_id:=1000}"
   echo "Local group: ${group:=www-data}:${group_id:=1000}"
   echo "LAN IP Address: ${lan_ip}"
   echo "Database server: ${MYSQL_HOST}"
   echo "Nextcloud database name: ${MYSQL_DATABASE:=nextcloud_db}"
   echo "Nextcloud database user: ${MYSQL_USER:=nextcloud}"
   echo "Nextcloud database password: ${MYSQL_PASSWORD:=NextcloudPass}"
   echo "Nextcloud Admin user: ${NEXTCLOUD_ADMIN_USER:=stackman}"
   echo "Nextcloud Admin password: ${NEXTCLOUD_ADMIN_PASSWORD:=Skibidibbydibyodadubdub}"
   echo "Nextcloud Update: ${NEXTCLOUD_UPDATE:=0}"
   if [ "${nextcloud_access_domain}" ]; then
      NEXTCLOUD_TRUSTED_DOMAINS="${media_access_domain} ${nextcloud_access_domain}"
   else
      NEXTCLOUD_TRUSTED_DOMAINS="${media_access_domain}"
   fi
   echo "Nextcloud access domain(s): $NEXTCLOUD_TRUSTED_DOMAINS"
   echo "Nextcloud installation root: /var/www/html"
   echo "Nextcloud web root: ${nextcloud_web_root:=/}"
   NEXTCLOUD_INSTALL_DIR="/var/www/html${nextcloud_web_root}"
   echo "Nextcloud install directory: ${NEXTCLOUD_INSTALL_DIR}"
   if [ ! -d "${NEXTCLOUD_INSTALL_DIR}" ]; then mkdir -p "${NEXTCLOUD_INSTALL_DIR}"; fi
   echo "Nextcloud data directory: ${NEXTCLOUD_DATA_DIR:=/var/www/data}"
   if [ ! -d "${NEXTCLOUD_DATA_DIR}" ]; then mkdir -p "${NEXTCLOUD_DATA_DIR}"; fi
   installed_version="0.0.0.0"
   export NEXTCLOUD_INSTALL_DIR
}

ChangeGroup(){
   if [ "${group_id}" ] && [ -z "$(getent group "${group_id}" | cut -d: -f3)" ]; then
      echo "Group ID available, changing group ID for www-data"
      groupmod -o www-data -g "${group_id}"
   elif [ ! "$(getent group "${group}" | cut -d: -f3)" = "${group_id}" ]; then
      echo "Group group_id in use, cannot continue"
      exit 1
   fi
}

ChangeUser(){
   if [ "${user_id}" ] && [ "${group_id}" ] && [ -z "$(getent passwd "${user}" | cut -d: -f3)" ]; then
      echo "User ID available, changing user and primary group"
      usermod -o www-data -u "${user_id}" -g "${group_id}"
   elif [ ! "$(getent passwd "${user}" | cut -d: -f3)" = "${user_id}" ]; then
      echo "User ID already in use - exiting"
      exit 1
   fi
}

ConfigureRedis(){
   echo "Configuring Redis as session handler"
   {
      echo 'session.save_handler = redis'
      # check if redis password has been set
      if [ -n "${REDIS_HOST_PASSWORD+x}" ]; then
          echo "session.save_path = \"tcp://${REDIS_HOST}:${REDIS_HOST_PORT:=6379}?auth=${REDIS_HOST_PASSWORD}\""
      else
          echo "session.save_path = \"tcp://${REDIS_HOST}:${REDIS_HOST_PORT:=6379}\""
      fi
   } > /usr/local/etc/php/conf.d/redis-session.ini
}

InstallNextcloud(){
   echo "starting nextcloud installation"
   max_retries=10
   try=0
   until run_as "/usr/local/bin/php ${NEXTCLOUD_INSTALL_DIR}/occ maintenance:install $install_options" || [ "$try" -gt "$max_retries" ]; do
      echo "Retrying install..."
      try=$((try+1))
      sleep 3s
   done
   if [ "$try" -gt "$max_retries" ]; then
      echo "Installing of nextcloud failed!"
      exit 1
   else
      run_as "echo y | $(which php) ${NEXTCLOUD_INSTALL_DIR}/occ db:convert-filecache-bigint"
   fi
}

SetTrustedDomains(){
   echo "Configure trusted domains..."
   NC_TRUSTED_DOMAIN_IDX=1
   for DOMAIN in $NEXTCLOUD_TRUSTED_DOMAINS ; do
      DOMAIN=$(echo "$DOMAIN" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      run_as "/usr/local/bin/php ${NEXTCLOUD_INSTALL_DIR}/occ config:system:set trusted_domains $NC_TRUSTED_DOMAIN_IDX --value=$DOMAIN"
      NC_TRUSTED_DOMAIN_IDX=$(($NC_TRUSTED_DOMAIN_IDX+1))
   done
}

PrepLaunch(){
   if expr "$1" : "apache" 1>/dev/null || [ "$1" = "php-fpm" ] || [ "${NEXTCLOUD_UPDATE:-0}" -eq 1 ]; then
      if [ -n "${REDIS_HOST+x}" ]; then ConfigureRedis; fi

      if [ -f "${NEXTCLOUD_INSTALL_DIR}/version.php" ]; then
         # shellcheck disable=SC2016
         installed_version="$(/usr/local/bin/php -r '$OC_Install_Dir = getenv("NEXTCLOUD_INSTALL_DIR"); require "$OC_Install_Dir/version.php"; echo implode(".", $OC_Version);')"
      fi
      # shellcheck disable=SC2016
      image_version="$(/usr/local/bin/php -r 'require "/usr/src/nextcloud/version.php"; echo implode(".", $OC_Version);')"
      if version_greater "$installed_version" "$image_version"; then
         echo "Can't start Nextcloud because the version of the data ($installed_version) is higher than the docker image version ($image_version) and downgrading is not supported. Are you sure you have pulled the newest image version?"
         exit 1
      fi

      if version_greater "$image_version" "$installed_version"; then
         echo "Initializing nextcloud $image_version ..."
         if [ "$installed_version" != "0.0.0.0" ]; then
            echo "Upgrading nextcloud from $installed_version ..."
            run_as "/usr/local/bin/php ${NEXTCLOUD_INSTALL_DIR}/occ app:list" | sed -n "/Enabled:/,/Disabled:/p" > /tmp/list_before
         fi
         if [ "$(id -u)" = 0 ]; then
            rsync_options="-rlDog --chown www-data:root"
         else
            rsync_options="-rlD"
         fi
         rsync $rsync_options --delete --exclude-from=/upgrade.exclude /usr/src/nextcloud/ "${NEXTCLOUD_INSTALL_DIR}/"

         for dir in config data custom_apps themes; do
            if [ ! -d "${NEXTCLOUD_INSTALL_DIR}/$dir" ] || directory_empty "${NEXTCLOUD_INSTALL_DIR}/$dir"; then
               rsync $rsync_options --include "/$dir/" --exclude '/*' /usr/src/nextcloud/ "${NEXTCLOUD_INSTALL_DIR}/"
            fi
         done
         rsync $rsync_options --include '/version.php' --exclude '/*' /usr/src/nextcloud/ "${NEXTCLOUD_INSTALL_DIR}/"
         echo "Initializing finished"

         #install
         if [ "$installed_version" = "0.0.0.0" ]; then
            echo "New nextcloud installation"
            if [ -n "${NEXTCLOUD_ADMIN_USER+x}" ] && [ -n "${NEXTCLOUD_ADMIN_PASSWORD+x}" ]; then
               # shellcheck disable=SC2016
               install_options="-n --admin-user $NEXTCLOUD_ADMIN_USER --admin-pass $NEXTCLOUD_ADMIN_PASSWORD"
               if [ -n "${NEXTCLOUD_TABLE_PREFIX+x}" ]; then
                  # shellcheck disable=SC2016
                  install_options=$install_options' --database-table-prefix "$NEXTCLOUD_TABLE_PREFIX"'
               fi
               if [ -n "${NEXTCLOUD_DATA_DIR+x}" ]; then
                  # shellcheck disable=SC2016
                  install_options=$install_options' --data-dir "$NEXTCLOUD_DATA_DIR"'
               fi
               install=false
               if [ -n "${MYSQL_DATABASE+x}" ] && [ -n "${MYSQL_USER+x}" ] && [ -n "${MYSQL_PASSWORD+x}" ] && [ -n "${MYSQL_HOST+x}" ]; then
                  echo "Installing with MySQL database"
                  # shellcheck disable=SC2016
                  install_options=$install_options' --database mysql --database-name "$MYSQL_DATABASE" --database-user "$MYSQL_USER" --database-pass "$MYSQL_PASSWORD" --database-host "$MYSQL_HOST"'
                  install=true
               fi
               if [ "$install" = true ]; then
                  InstallNextcloud
               else
                  echo "Running web-based installer on first connect!"
               fi
            fi
         else
            #upgrade
            run_as '/usr/local/bin/php "${NEXTCLOUD_INSTALL_DIR}/occ" upgrade'
            run_as '/usr/local/bin/php "${NEXTCLOUD_INSTALL_DIR}/occ" app:list' | sed -n "/Enabled:/,/Disabled:/p" > /tmp/list_after
            echo "The following apps have been disabled:"
            diff /tmp/list_before /tmp/list_after | grep '<' | cut -d- -f2 | cut -d: -f1
            rm -f /tmp/list_before /tmp/list_after
         fi
      fi
   fi
}

FirstRun(){
   echo "First run detected, create default settings"
   os_release="$(cat /etc/os-release | grep ^"ID=" | cut -d= -f2)"
   if [ "${os_release}" = "alpine" ]; then
      echo "Backup PHP config files"
      cp /usr/local/etc/php-fpm.d/www.conf /usr/local/etc/php-fpm.d/www.conf.default
      cp /usr/local/etc/php-fpm.conf /usr/local/etc/php-fpm.conf.default
      cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
      cp /usr/local/etc/php/php.ini /usr/local/etc/php/php.ini.default
      if [ -f "/usr/local/etc/php-fpm.d/docker.conf" ]; then rm "/usr/local/etc/php-fpm.d/docker.conf"; fi
      if [ -f "/usr/local/etc/php-fpm.d/zz-docker.conf" ]; then rm "/usr/local/etc/php-fpm.d/zz-docker.conf"; fi
      echo "Configure PHP config options"
      sed -i -e 's#^doc_root =*#doc_root = /var/www/html#' \
         -e 's#^memory_limit =.*#memory_limit = 512M#' \
         -e 's#^output_buffering =.*#output_buffering = Off#' \
         -e 's#^max_execution_time =.*#max_execution_time = 1800#' \
         -e 's#^max_input_time =.*#max_input_time = 3600#' \
         -e 's#^post_max_size =.*#post_max_size = 10G#' \
         -e 's#^upload_max_filesize =.*#upload_max_filesize = 10G#' \
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
      echo "Create PHP pool options"
      {
         echo '[www]'
         echo 'user = www-data'
         echo 'group = www-data'
         echo 'listen = 127.0.0.1:9000'
         echo 'pm = dynamic'
         echo 'pm.max_children = 240'
         echo 'pm.start_servers = 6'
         echo 'pm.min_spare_servers = 3'
         echo 'pm.max_spare_servers = 9'
         echo 'pm.max_requests = 250'
         echo 'pm.status_path = /status'
         echo 'access.log = /dev/stderr'
         echo 'env[HOSTNAME] = $HOSTNAME'
         echo 'env[PATH] = /usr/local/bin:/usr/bin:/bin'
         echo 'env[TMP] = /tmp'
         echo 'env[TMPDIR] = /tmp'
         echo 'env[TEMP] = /tmp'
      } > /usr/local/etc/php-fpm.d/www.conf
      echo "Create PHP-FPM options"
      {
         echo '[global]'
         echo 'error_log = /dev/stderr'
         echo 'log_level = notice'
         echo 'emergency_restart_threshold = 10'
         echo 'emergency_restart_interval = 1m'
         echo 'process_control_timeout = 10s'
         echo 'daemonize = no'
         echo 'include=/usr/local/etc/php-fpm.d/*.conf'
      } > /usr/local/etc/php-fpm.conf
   elif [ "${os_release}" = "debian" ]; then
      echo "Backup PHP config files"
      cp "/etc/php/7.3/fpm/php.ini" "/etc/php/7.3/fpm/php.ini.default"
      mv "/etc/php/7.3/fpm/pool.d/www.conf" "/etc/php/7.3/fpm/pool.d/www.conf.default"
      if [ -f "/etc/php/7.3/fpm/php-fpm.conf-production" ]; then mv "/etc/php/7.3/fpm/php-fpm.conf-production" "/etc/php/7.3/fpm/php-fpm.conf-production.default"; fi
      mv "/etc/php/7.3/fpm/php-fpm.conf" "/etc/php/7.3/fpm/php-fpm.conf.default"
      if [ -f "/usr/local/etc/php-fpm.d/docker.conf" ]; then rm "/usr/local/etc/php-fpm.d/docker.conf"; fi
      if [ -f "/usr/local/etc/php-fpm.d/zz-docker.conf" ]; then rm "/usr/local/etc/php-fpm.d/zz-docker.conf"; fi
      echo "Configure PHP config options"
      sed -i \
         -e 's#^doc_root.*#doc_root = /var/www/html#' \
         -e 's#^memory_limit =.*#memory_limit = 512M#' \
         -e 's#^output_buffering =.*#output_buffering = Off#' \
         -e 's#^max_execution_time =.*#max_execution_time = 1800#' \
         -e 's#^max_input_time =.*#max_input_time = 3600#' \
         -e 's#^post_max_size =.*#post_max_size = 10G#' \
         -e 's#^upload_max_filesize =.*#upload_max_filesize = 10G#' \
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
         "/etc/php/7.3/fpm/php.ini"
      echo "Create PHP pool options"
      {
         echo '[www]'
         echo 'user = www-data'
         echo 'group = www-data'
         echo 'listen = 127.0.0.1:9000'
         echo 'pm = dynamic'
         echo 'pm.max_children = 240'
         echo 'pm.start_servers = 6'
         echo 'pm.min_spare_servers = 3'
         echo 'pm.max_spare_servers = 9'
         echo 'pm.max_requests = 250'
         echo 'pm.status_path = /status'
         echo 'access.log = /var/log/php7.3-fpm.log'
         echo 'env[HOSTNAME] = $HOSTNAME'
         echo 'env[PATH] = /usr/local/bin:/usr/bin:/bin'
         echo 'env[TMP] = /tmp'
         echo 'env[TMPDIR] = /tmp'
         echo 'env[TEMP] = /tmp'
      } > "/etc/php/7.3/fpm/pool.d/www.conf"
      echo "Create PHP-FPM options"
      {
         echo '[global]'
         echo 'error_log = /dev/stderr'
         echo ';error_log = /var/log/php7.3-fpm.log'
         echo 'log_level = notice'
         echo 'emergency_restart_threshold = 10'
         echo 'emergency_restart_interval = 1m'
         echo 'process_control_timeout = 10s'
         echo 'daemonize = no'
         echo 'include=/etc/php/7.3/fpm/pool.d/www.conf'
      } > "/etc/php/7.3/fpm/php-fpm.conf"
   else
      echo "OS not recognised - exiting"
      sleep 120
      exit 1
   fi
   if [ -f "${NEXTCLOUD_INSTALL_DIR}/config/config.php" ]; then
      echo "${NEXTCLOUD_INSTALL_DIR}/config/config.php - Exists"
      if [ "$(grep -c "blacklisted_files" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'blacklisted_files' =>"
            echo "  array ("
            echo "     0 => '.htaccess',"
            echo "     1 => 'Thumbs.db',"
            echo "     2 => 'thumbs.db',"
            echo "  ),"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "cron_log" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'cron_log' => true,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "enable_previews" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'enable_previews' => true,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "enabledPreviewProviders" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'enabledPreviewProviders' =>"
            echo "  'preview_max_x' => 1280,"
            echo "  'preview_max_y' => 1024,"
            echo "  array ("
            echo "    0 => 'OC\\Preview\\PNG',"
            echo "    1 => 'OC\\Preview\\JPEG',"
            echo "    2 => 'OC\\Preview\\GIF',"
            echo "    3 => 'OC\\Preview\\BMP',"
            echo "    4 => 'OC\\Preview\\XBitmap',"
            echo "    5 => 'OC\\Preview\\Movie',"
            echo "    6 => 'OC\\Preview\\PDF',"
            echo "    7 => 'OC\\Preview\\MP3',"
            echo "    8 => 'OC\\Preview\\TXT',"
            echo "    9 => 'OC\\Preview\\MarkDown',"
            echo "  ),"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "preview_max_scale_factor" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'preview_max_scale_factor' => 1,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "filesystem_check_changes" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'filesystem_check_changes' => 0,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "filelocking.enabled" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'filelocking.enabled' => 'true',"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "htaccess.RewriteBase" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'htaccess.RewriteBase' => '/',"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "integrity.check.disabled" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'integrity.check.disabled' => false,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "knowledgebaseenabled" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'knowledgebaseenabled' => false,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "logfile" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'logfile' => '/dev/stdout',"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "loglevel" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'loglevel' => 2,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "logtimezone" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'logtimezone' => '${TZ}',"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "logtimezone" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'logtimezone' => '${TZ}',"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
# echo "  'log_rotate_size' => 104857600,"
      if [ "$(grep -c "trashbin_retention_obligation" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'trashbin_retention_obligation' => 'auto, 7',"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "updater.release.channel" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'updater.release.channel' => 'stable',"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "updatechecker" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'updatechecker' => false,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "check_for_working_htaccess" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'check_for_working_htaccess' => false,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "overwriteprotocol" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'overwriteprotocol' => 'https',"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "overwritewebroot" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'overwritewebroot' => '/${nextcloud_web_root/\/}',"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "auth.bruteforce.protection.enabled" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'auth.bruteforce.protection.enabled' => true,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "maintenance" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'maintenance' => false,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      if [ "$(grep -c "installed" "${NEXTCLOUD_INSTALL_DIR}/config/config.php")" -eq 0 ]; then
         sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
         { 
            echo "  'installed' => true,"
            echo ");"
         } >> "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      fi
      echo "First-run initialisation complete"
      rm "/initialise_container"
   fi
}

Configure(){
   echo "Configure php-fpm listen address"
   sed -i \
      -e "s%listen =.*%listen = ${lan_ip}:9001%" \
      /usr/local/etc/php-fpm.d/www.conf
}

SetCrontab(){
   echo "Configure crontab: ${NEXTCLOUD_INSTALL_DIR}"
   echo "*/15 * * * * /usr/local/bin/php -f \"${NEXTCLOUD_INSTALL_DIR}/cron.php\"" > "/var/spool/cron/crontabs/www-data"
}

SetOwnerAndGroup(){
   echo "Correct owner and group of application files, if required"
   find "${NEXTCLOUD_INSTALL_DIR}" ! -user "${user_id}" -exec chown "${user_id}" {} \;
   find "${NEXTCLOUD_INSTALL_DIR}" ! -group "${group_id}" -exec chgrp "${group_id}" {} \;
   find "${NEXTCLOUD_DATA_DIR}" ! -user "${user_id}" -exec chown "${user_id}" {} \;
   find "${NEXTCLOUD_DATA_DIR}" ! -group "${group_id}" -exec chgrp "${group_id}" {} \;
}

##### Script #####
WaitForDBServer
Initialise
ChangeGroup
ChangeUser
SetOwnerAndGroup
PrepLaunch "$1"
if [ -f "/initialise_container" ]; then FirstRun; fi
Configure
SetCrontab
SetOwnerAndGroup
if [ -n "${NEXTCLOUD_TRUSTED_DOMAINS+x}" ]; then SetTrustedDomains; fi
exec "$@"