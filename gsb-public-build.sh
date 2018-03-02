#!/bin/bash

convertsecs() {
  m=$(($1 % 3600 / 60))
  s=$(($1 % 60))
  printf "%02d:%02d\n" $m $s
}

# Get global variables
if [ -e conf/global.cfg ]; then
  source conf/global.cfg
else
  echo "[Build] global.cfg not found."
fi

if [ -e conf/lastbranch.cfg ]; then
  source conf/lastbranch.cfg
  DEFAULT_BRANCH = $LAST_BRANCH
fi

# Location of where we put the build artifacts.
# gsb-public-build.sh       # SCRIPT_DIR
#  -> build                 # BUILD_DIR
#     -> gsb-public-distro  # BUILD_DISTRO_DIR
#     -> www                # BUILD_WWW_DIR
#     -> tmp                # BUILD_TMP_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR=$SCRIPT_DIR/build
BUILD_DISTRO_DIR=$BUILD_DIR/$DISTRO-distro
BUILD_MAKE_DIR=$BUILD_DIR/gsb_public
BUILD_TMP_DIR=$BUILD_DIR/drupal-tmp
BUILD_WWW_DIR=$SCRIPT_DIR/src

# Check for missing variables.
ERROR=false
if [ -z $DRUSH_PATH ]; then
  echo "The \$DRUSH_PATH variable needs to be set."
  ERROR=true
fi

if [ -z $BUILD_WWW_DIR ]; then
  echo "The \$BUILD_WWW_DIR variable needs to be set."
  ERROR=true
fi

if [ -z $BUILD_TMP_DIR ]; then
  echo "The \$BUILD_TMP_DIR variable needs to be set."
  ERROR=true
fi

if [ -z $DB_USERNAME ]; then
  echo "The \$DB_USERNAME variable needs to be set."
  ERROR=true
fi

if [ -z $DB_PASS ]; then
  echo "The \$DB_PASS variable needs to be set."
  ERROR=true
fi

if [ ! -w "$PROD_TMP" ]; then
  echo "The temporary directory $PROD_TMP needs to exist and be writable."
  ERROR=true
fi

# If anything is missing then exit.
if [ $ERROR = true ]; then
  exit
fi

echo "Build Options";
echo "[1] Full Build: Runs make and downloads fresh database from production"
echo "[2] Quick Build: Restores files and database from last full build"
echo "[3] Restore files only: Restores files from last full build"
echo "[4] Restore database only:  Restores database from last full build"
echo "[5] Cancel"
read -e -p ":" BUILD_OPTION

if [ $BUILD_OPTION = 1 ]; then
  read -e -p "Enter the branch to use [$DEFAULT_BRANCH]: " BRANCH
  # If nothing is specified then use the specified default.
  if [ ! -n "$BRANCH" ]; then
    BRANCH=$DEFAULT_BRANCH
  else
    echo "LAST_BRANCH = $BRANCH" > conf/lastbranch.cfg
  fi
fi

# Create build directory if it doesn't exist.
if [ ! -d "$BUILD_DIR" ]; then
  echo "[Build] Initialize build directory"
  mkdir "$BUILD_DIR"
fi

# Create build directory if it doesn't exist.
if [ ! -d "$BUILD_TMP_DIR" ]; then
  echo "[Build] Initialize temp directory"
  mkdir "$BUILD_TMP_DIR"
fi

# Remove the old installation directory
rm -Rf $BUILD_WWW_DIR

if [ $BUILD_OPTION = 1 ]; then
  # Start our counter.
  START_TIME=$SECONDS

  # Setup the distro directory.
  if [ ! -d "$BUILD_DISTRO_DIR" ]; then
    cd $BUILD_DIR
    git clone $DISTRO_GIT_URL
  fi

  # Checkout chosen branch.
  cd $BUILD_DISTRO_DIR
  git pull
  git checkout $BRANCH

  # Move into our apache root and run drush make and/or replace the db.
  echo "Deleting Old $BUILD_MAKE_DIR"
  rm -Rf $BUILD_MAKE_DIR
  echo "Run drush make and dump the database. This can take upwards of 15 minutes."
  php $DRUSH_PATH make --working-copy $BUILD_DISTRO_DIR/$DISTRO-distro.make $BUILD_MAKE_DIR

  php $DRUSH_PATH @$SITE_ALIAS.$BASE_ENV sql-dump --structure-tables-list="cache,cache_*,history,search_*,sessions,watchdog" > $BUILD_DIR/$BASE_ENV.sql
  wait
  echo "Import the database"
  mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf -e "DROP DATABASE $DB_NAME;"
  mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf -e "CREATE DATABASE $DB_NAME;"
  mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf $DB_NAME < $BUILD_DIR/$BASE_ENV.sql
  ELAPSED_TIME=$(($SECONDS - $START_TIME))
  echo "Make Time: " $(convertsecs $ELAPSED_TIME)

  rm -Rf $BUILD_MAKE_DIR/sites/default
  cp -R $SCRIPT_DIR/assets/$DISTRO/default $BUILD_MAKE_DIR/sites
  ln -s $BUILD_MAKE_DIR/sites/default $BUILD_MAKE_DIR/sites/gsb
  chmod -R 777 $BUILD_MAKE_DIR/sites

  # replace database credentials
  if [[ $platform == 'linux' ]]; then
    sed -i "s/---db-username---/$DB_USERNAME/g" $BUILD_MAKE_DIR/sites/default/settings.php
    sed -i "s/---db-password---/$DB_PASS/g" $BUILD_MAKE_DIR/sites/default/settings.php
    sed -i "s/---db-name---/$DB_NAME/g" $BUILD_MAKE_DIR/sites/default/settings.php
    sed -i "s/---db-url---/$DB_URL/g" $BUILD_MAKE_DIR/sites/default/settings.php
    sed -i "s/---db-port---/$DB_PORT/g" $BUILD_MAKE_DIR/sites/default/settings.php
  elif [[ $platform == 'macos' ]]; then
    sed -i .bk "s/---db-username---/$DB_USERNAME/g" $BUILD_MAKE_DIR/sites/default/settings.php
    sed -i .bk "s/---db-password---/$DB_PASS/g" $BUILD_MAKE_DIR/sites/default/settings.php
    sed -i .bk "s/---db-name---/$DB_NAME/g" $BUILD_MAKE_DIR/sites/default/settings.php
    sed -i .bk "s/---db-url---/$DB_URL/g" $BUILD_MAKE_DIR/sites/default/settings.php
    sed -i .bk "s/---db-port---/$DB_PORT/g" $BUILD_MAKE_DIR/sites/default/settings.php
  fi

  cp $SCRIPT_DIR/assets/.htaccess $BUILD_MAKE_DIR/.htaccess

  echo "BUILD Copy make files to apache folder"
  if [ ! -d "$BUILD_WWW_DIR" ]; then
    echo "Creating $BUILD_WWW_DIR"
    mkdir -p $BUILD_WWW_DIR
  fi
  cp -fr $BUILD_MAKE_DIR $BUILD_WWW_DIR
fi

echo "Set site variables"
cd $BUILD_WWW_DIR/gsb_public
php $DRUSH_PATH upwd --password=admin admin
php $DRUSH_PATH vset file_temporary_path $BUILD_TMP_DIR
php $DRUSH_PATH vset cache 0
php $DRUSH_PATH vset preprocess_css 0
php $DRUSH_PATH vset preprocess_js 0
php $DRUSH_PATH vset error_level 2

echo "Disable Memcache, Acquia and Shield"
php $DRUSH_PATH dis -y memcache_admin acquia_purge acquia_agent shield

echo "Run database updates"
php $DRUSH_PATH updb -y

echo "Revert features"
php $DRUSH_PATH fra -y

#echo "Enable Stage File Proxy and Devel"
php $DRUSH_PATH en -y devel stage_file_proxy
php $DRUSH_PATH vset stage_file_proxy_origin $REMOTE_URL

echo "Enable Kraken"
php -r "print json_encode(array('api_key'=> '$KRAKEN_KEY', 'api_secret'=> '$KRAKEN_SECRET'));" | $DRUSH_PATH vset --format=json kraken -

echo "Enable views development setup."
php $DRUSH_PATH vd
php $DRUSH_PATH cc all

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "Total Time: " $(convertsecs $ELAPSED_TIME)

# Send a notification saying we are done.
echo "The build has completed successfully."
echo "release built is: " $BRANCH > gsb_build_options.txt
echo "base env is: " $BASE_ENV >> gsb_build_options.txt
echo "db refresh is: " $REFRESH >> gsb_build_options.txt
echo "use make is: " $USE_MAKE >> gsb_build_options.txt
