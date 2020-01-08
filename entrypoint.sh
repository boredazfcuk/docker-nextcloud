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
   echo -e "\n"
   echo "***** Starting Nextcloud container *****"
   if [ -z "${MYSQL_HOST}" ]; then
      echo "MYSQL_HOST variable not set, exiting"
      exit 1
   fi
   if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
      echo "MYSQL_ROOT_PASSWORD variable not set, exiting"
      exit 1
   fi
   DBSERVERONLINE="$(mysql --host="${MYSQL_HOST}" --user=root --password="${MYSQL_ROOT_PASSWORD}" --execute="SELECT 1;" 2>/dev/null | grep -c "1")"
   while [ "${DBSERVERONLINE}" = 0 ]; do
      echo "Waiting for database server, ${MYSQL_HOST}, to come online..." 
      sleep 10
      DBSERVERONLINE="$(mysql --host="${MYSQL_HOST}" --user=root --password="${MYSQL_ROOT_PASSWORD}" --execute="SELECT 1;" 2>/dev/null | grep -c "1")" 
   done
}

Initialise(){
   if [ -z "${USER}" ]; then echo "User name not set, defaulting to 'nextcloud'"; USER="nextcloud"; fi
   if [ -z "${UID}" ]; then echo "User ID not set, defaulting to '1000'"; UID="1000"; fi
   if [ -z "${GROUP}" ]; then echo "Group name not set, defaulting to 'www-data'"; GROUP="www-data"; fi
   if [ -z "${GID}" ]; then echo "Group ID not set, defaulting to '1000'"; GID="1000"; fi
   echo "Local user: ${USER}:${UID}"
   echo "Local group: ${GROUP}:${GID}"
   echo "Database server: ${MYSQL_HOST}"
   echo "Nextcloud database name: ${MYSQL_DATABASE}"
   echo "Nextcloud database user: ${MYSQL_USER:=nextcloud}"
   echo "Nextcloud database password: ${MYSQL_PASSWORD:=NextcloudPass}"
   echo "Nextcloud Admin user: ${NEXTCLOUD_ADMIN_USER:=stackman}"
   echo "Nextcloud Admin password: ${NEXTCLOUD_ADMIN_PASSWORD:=Skibidibbydibyodadubdub}"
   echo "Nextcloud access domain: $NEXTCLOUD_TRUSTED_DOMAINS"
   if [ ! -z "${NEXTCLOUD_BASE_DIR}" ]; then
      echo "Nextcloud web root: ${NEXTCLOUD_BASE_DIR}"
      export NEXTCLOUD_INSTALL_DIR="/var/www/html${NEXTCLOUD_BASE_DIR}"
      echo "Nextcloud install path: ${NEXTCLOUD_INSTALL_DIR}"
   else
      export NEXTCLOUD_INSTALL_DIR="/var/www/html"
      echo "Nextcloud install path: ${NEXTCLOUD_INSTALL_DIR}"
   fi
   echo "Nextcloud data directory: ${NEXTCLOUD_DATA_DIR:=/var/www/data}"
   if [ ! -d "${NEXTCLOUD_DATA_DIR}" ]; then mkdir -p "${NEXTCLOUD_DATA_DIR}"; fi
   echo "Nextcloud installation directory ${NEXTCLOUD_INSTALL_DIR}"
   if [ ! -d "${NEXTCLOUD_INSTALL_DIR}" ]; then mkdir -p "${NEXTCLOUD_INSTALL_DIR}"; fi
   installed_version="0.0.0.0"
}

ChangeGroup(){
   if [ ! -z "${GID}" ] && [ -z "$(getent group "${GID}" | cut -d: -f3)" ]; then
      echo "Group ID available, changing group ID for www-data"
      groupmod -o www-data -g "${GID}"
   elif [ ! "$(getent group "${GROUP}" | cut -d: -f3)" = "${GID}" ]; then
      echo "Group GID in use, cannot continue"
      exit 1
   fi
}

ChangeUser(){
   if [ ! -z "${UID}" ] && [ ! -z "${GID}" ] && [ -z "$(getent passwd "${USER}" | cut -d: -f3)" ]; then
      echo "User ID available, changing user and primary group"
      usermod -o www-data -u "${UID}" -g "${GID}"
   elif [ ! "$(getent passwd "${USER}" | cut -d: -f3)" = "${UID}" ]; then
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
      echo "retrying install..."
      try=$((try+1))
      sleep 3s
   done
   if [ "$try" -gt "$max_retries" ]; then
      echo "installing of nextcloud failed!"
      exit 1
   fi
}

SetTrustedDomains(){
   echo "setting trusted domains…"
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
                   if [ -n "${NEXTCLOUD_TABLE_PREFIX+x}" ] && [ "${NEXTCLOUDDBEXISTS}" = 0 ]; then
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
                       echo "running web-based installer on first connect!"
                   fi
                   if [ -n "${NEXTCLOUD_TRUSTED_DOMAINS+x}" ]; then
                     SetTrustedDomains
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
   echo "Backup PHP config files"
   cp /usr/local/etc/php-fpm.d/www.conf /usr/local/etc/php-fpm.d/www.conf.default
   cp /usr/local/etc/php-fpm.conf /usr/local/etc/php-fpm.conf.default
   cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
   cp /usr/local/etc/php/php.ini /usr/local/etc/php/php.ini.default
   echo "Set PHP config options"
   sed -i -e 's#^doc_root =*#doc_root = /var/www/html#' \
      -e 's#^memory_limit =.*#memory_limit = 512M#' \
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
   echo "Set PHP pool options"
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
   echo "Set PHP-FPM options"
   sed -i -e 's#;error_log =.*#error_log = /dev/stderr#' \
      -e 's#;log_level =.*#log_level = notice#' \
      -e 's#;daemonize =.*#daemonize = no#' \
      -e 's#;emergency_restart_threshold =.*#emergency_restart_threshold = 10#' \
      -e 's#;emergency_restart_interval =.*#emergency_restart_interval = 1m#' \
      -e 's#;process_control_timeout =.*#process_control_timeout = 10s#' \
      /usr/local/etc/php-fpm.conf
   if [ -f "${NEXTCLOUD_INSTALL_DIR}/config/config.php" ]; then
      echo "${NEXTCLOUD_INSTALL_DIR}/config/config.php - Exists"
      sed -i '$d' "${NEXTCLOUD_INSTALL_DIR}/config/config.php"
      { 
          echo "  'blacklisted_files' =>"
          echo "      array ("
          echo "         0 => '.htaccess',"
          echo "         1 => 'Thumbs.db',"
          echo "         2 => 'thumbs.db',"
          echo "      ),"
          echo "  'cron_log' => true,"
          echo "  'enable_previews' => true,"
          echo "  'enabledPreviewProviders' =>"
          echo "     array ("
          echo "        0 => 'OC\\Preview\\PNG',"
          echo "        1 => 'OC\\Preview\\JPEG',"
          echo "        2 => 'OC\\Preview\\GIF',"
          echo "        3 => 'OC\\Preview\\BMP',"
          echo "        4 => 'OC\\Preview\\XBitmap',"
          echo "        5 => 'OC\\Preview\\Movie'",
          echo "        6 => 'OC\\Preview\\PDF',"
          echo "        7 => 'OC\\Preview\\MP3',"
          echo "        8 => 'OC\\Preview\\TXT',"
          echo "        9 => 'OC\\Preview\\MarkDown',"
          echo "     ),"
          echo "  'preview_max_x' => 1024,"
          echo "  'preview_max_y' => 768,"
          echo "  'preview_max_scale_factor' => 1,"
          echo "  'filesystem_check_changes' => 0,"
          echo "  'filelocking.enabled' => 'true',"
          echo "  'htaccess.RewriteBase' => '/',"
          echo "  'integrity.check.disabled' => false,"
          echo "  'knowledgebaseenabled' => false,"
          echo "  'logfile' => '/dev/stdout',"
          echo "  'loglevel' => 2,"
          echo "  'logtimezone' => '${TZ}',"
          echo "  'log_rotate_size' => 104857600,"
          echo "  'trashbin_retention_obligation' => 'auto, 7',"
          echo "  'updater.release.channel' => 'stable',"
          echo "  'updatechecker' => false,"
          echo "  'check_for_working_htaccess' => false,"
          echo "  'overwriteprotocol' => 'https',"
          echo "  'overwritewebroot' => '/${NEXTCLOUD_BASE_DIR/\/}',"
          echo "  'auth.bruteforce.protection.enabled' => true,"
          echo "  'maintenance' => false,"
          echo "  'installed' => true,"
          echo ");"
      } >> "/var/www/html${NEXTCLOUD_BASE_DIR}/config/config.php"
   fi
}

SetCrontab(){
   echo "Add crontab"
    if [ ! -z "${NEXTCLOUD_BASE_DIR}" ]; then
        echo '*/15 * * * * /usr/local/bin/php -f "/var/www/html'"${NEXTCLOUD_BASE_DIR}"'/cron.php"' > "/var/spool/cron/crontabs/www-data"
    else
        echo "Add crontab"
        echo '*/15 * * * * /usr/local/bin/php -f "/var/www/html/cron.php"' > "/var/spool/cron/crontabs/www-data"
    fi
}

SetOwnerAndGroup(){
   echo "Correct owner and group of application files, if required"
   find "/var/www/html" ! -user "${UID}" -exec chown "${UID}" {} \;
   find "/var/www/html" ! -group "${GID}" -exec chgrp "${GID}" {} \;
   find "${NEXTCLOUD_DATA_DIR}" ! -user "${UID}" -exec chown "${UID}" {} \;
   find "${NEXTCLOUD_DATA_DIR}" ! -group "${GID}" -exec chgrp "${GID}" {} \;
}

##### Script #####
WaitForDBServer
Initialise
ChangeGroup
ChangeUser
SetOwnerAndGroup
PrepLaunch "$1"
if [ ! -f "/usr/local/etc/php/php.ini" ]; then FirstRun; fi
SetCrontab
SetOwnerAndGroup
exec "$@"
