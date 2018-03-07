#!/bin/bash
import_database() {
  echo "[Build] Import the database"
  mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf -e "DROP DATABASE $DB_NAME;"
  mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf -e "CREATE DATABASE $DB_NAME;"
  mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf $DB_NAME < $BUILD_DIR/prod.sql
}

copy_make_files_to_www() {
  echo "[Build] Copying build files to source directory"
  rm -Rf $BUILD_WWW_DIR
  mkdir -p $BUILD_WWW_DIR
  cp -fr $BUILD_MAKE_DIR $BUILD_WWW_DIR
}

post_database_operations() {
  echo "[Build] Set site variables"
  cd $BUILD_WWW_DIR/gsb_public
  php $DRUSH_PATH upwd --password=admin admin
  php $DRUSH_PATH vset file_temporary_path $BUILD_TMP_DIR
  php $DRUSH_PATH vset cache 0
  php $DRUSH_PATH vset preprocess_css 0
  php $DRUSH_PATH vset preprocess_js 0
  php $DRUSH_PATH vset error_level 2

  echo "[Build] Disable Memcache, Acquia and Shield"
  php $DRUSH_PATH dis -y memcache_admin acquia_purge acquia_agent shield

  echo "[Build] Run database updates"
#  php $DRUSH_PATH updb -y

  echo "[Build] Revert features"
#  php $DRUSH_PATH fra -y

  #echo "Enable Stage File Proxy and Devel"
  php $DRUSH_PATH en -y devel stage_file_proxy
  php $DRUSH_PATH vset stage_file_proxy_origin $REMOTE_URL

  echo "[Build] Enable Kraken"
  php -r "print json_encode(array('api_key'=> '$KRAKEN_KEY', 'api_secret'=> '$KRAKEN_SECRET'));" | $DRUSH_PATH vset --format=json kraken -

  echo "[Build] Enable views development setup."
  php $DRUSH_PATH vd
}

configure_drupal_sites_dir() {
  echo "[Build] Configure drupal sites/default directory"
  rm -Rf $BUILD_MAKE_DIR/sites/default
  cp -R $SCRIPT_DIR/assets/$DISTRO/default $BUILD_MAKE_DIR/sites
  ln -s $BUILD_MAKE_DIR/sites/default $BUILD_MAKE_DIR/sites/gsb
  chmod -R 777 $BUILD_MAKE_DIR/sites
  echo "[Build] .htaccess to prevent https:// in development"
  cp $SCRIPT_DIR/assets/.htaccess $BUILD_MAKE_DIR/.htaccess

  # replace database credentials
  if [[ $platform == 'linux' ]]; then
    SED_CMD="-i"
  elif [[ $platform == 'macos' ]]; then
    SED_CMD="-i .bk"
  fi
  sed $SED_CMD "s/---db-username---/$DB_USERNAME/g" $BUILD_MAKE_DIR/sites/default/settings.php
  sed $SED_CMD "s/---db-password---/$DB_PASS/g" $BUILD_MAKE_DIR/sites/default/settings.php
  sed $SED_CMD "s/---db-name---/$DB_NAME/g" $BUILD_MAKE_DIR/sites/default/settings.php
  sed $SED_CMD "s/---db-url---/$DB_URL/g" $BUILD_MAKE_DIR/sites/default/settings.php
  sed $SED_CMD "s/---db-port---/$DB_PORT/g" $BUILD_MAKE_DIR/sites/default/settings.php
}

get_gsb-public_distro() {
  echo "[Build] Get the gsb_public distribution file"
  # Setup the distro directory.
  if [ ! -d "$BUILD_DISTRO_DIR" ]; then
    cd $BUILD_DIR
    git clone $DISTRO_GIT_URL
  fi
  # Checkout chosen branch.
  cd $BUILD_DISTRO_DIR
  git pull
  git checkout $BRANCH
}

run_drush_make() {
  echo "[Build] Running Drush Make."
  rm -Rf $BUILD_MAKE_DIR
  php $DRUSH_PATH make --working-copy $BUILD_DISTRO_DIR/$DISTRO-distro.make $BUILD_MAKE_DIR
}

export_db_from_acquia() {
  echo "[Build] Export database from Acquia"
  php $DRUSH_PATH @$SITE_ALIAS.prod sql-dump --structure-tables-list="cache,cache_*,history,search_*,sessions,watchdog" > $BUILD_DIR/prod.sql
  wait
}

convertsecs() {
  m=$(($1 % 3600 / 60))
  s=$(($1 % 60))
  printf "%02d:%02d\n" $m $s
}