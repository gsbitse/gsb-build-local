#!/bin/bash
convertsecs() {
    m=$(( $1  % 3600 / 60 ))
    s=$(( $1 % 60 ))
    printf "%02d:%02d\n" $m $s
}


# Get global variables
if [ -e conf/global.cfg ]; then
  source conf/global.cfg
else
  echo "[Build] global.cfg not found."
fi

# Location of where we put the build artifacts.
# gsb-public-build.sh       # SCRIPT_DIR
#  -> build                 # BUILD_DIR
#     -> gsb-public-distro  # BUILD_DISTRO_DIR
#     -> www                # BUILD_WWW_DIR
#     -> tmp                # BUILD_TMP_DIR

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR=$SCRIPT_DIR/build
BUILD_DISTRO_DIR=$BUILD_DIR/$DISTRO-distro
BUILD_MAKE_DIR=$BUILD_DIR/gsb_public
BUILD_WWW_DIR=$BUILD_DIR/www
BUILD_TMP_DIR=$BUILD_DIR/drupal-tmp

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

# Read the base environment.
read -e -p "Should the database be refreshed from the server? [y/N]: " REFRESH_CHOICE

# If nothing is specified then use the specified default.
REFRESH=false
if [[ $REFRESH_CHOICE = "y" ]] || [[ $REFRESH_CHOICE = "Y" ]]; then
  REFRESH=true
fi

# Read the option of using the make file.
read -e -p "Should this run a drush make? (Otherwise it will get the code from an environment of your choice) [y/N]: " USE_MAKE_CHOICE

# Use make decision
USE_MAKE=false
if [[ $USE_MAKE_CHOICE = "y" ]] || [[ $USE_MAKE_CHOICE = "Y" ]]; then
  USE_MAKE=true
fi

# Only ask for environment if it's needed.
if [ $REFRESH = true ] || [ $USE_MAKE = false ]; then

  # Read the base environment.
  read -e -p "Enter the environment to base the site on [$DEFAULT_BASE_ENV]: " BASE_ENV

  # If nothing is specified then use the specified default.
  if [ ! -n "$BASE_ENV" ]; then
    BASE_ENV=$DEFAULT_BASE_ENV
  fi

  # Since acquia is confusing allowing stage and stage2 to be used along with
  # test and test2
  if [ $BASE_ENV = "stage" ]; then
    BASE_ENV="test"
  elif [ $BASE_ENV = "stage2" ]; then
    BASE_ENV="test2"
  fi

  # Get the url to use for stage_file_proxy.
  REMOTE_URL=http://public2-$BASE_ENV.gsb.stanford.edu
  if [[ $BASE_ENV = "prod" ]]; then
    REMOTE_URL=http://gsb.stanford.edu
  elif [[ $BASE_ENV = "test" ]]; then
    REMOTE_URL=http://public2-stage.gsb.stanford.edu
  elif [[ $BASE_ENV = "test2" ]]; then
    REMOTE_URL=http://public2-stage2.gsb.stanford.edu
  fi

fi

# Remove the old installation directory
sudo rm -Rf $BUILD_WWW_DIR

if [ $USE_MAKE = true ]; then
  # Figure out which branch
  read -e -p "Enter the branch to use [$DEFAULT_BRANCH]: " BRANCH

  # If nothing is specified then use the specified default.
  if [ ! -n "$BRANCH" ]; then
    BRANCH=$DEFAULT_BRANCH
  fi

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
  if [ $REFRESH = true ]; then
    echo "Deleting Old $BUILD_MAKE_DIR"
    sudo rm -Rf $BUILD_MAKE_DIR
    echo "Run drush make and dump the database. This can take upwards of 15 minutes."
    php $DRUSH_PATH make --working-copy $BUILD_DISTRO_DIR/$DISTRO-distro.make $BUILD_MAKE_DIR

    echo "BUILD Copy make files to apache folder"
    if [ ! -d "$BUILD_WWW_DIR" ]; then
    echo "Creating $BUILD_WWW_DIR"
        mkdir -p $BUILD_WWW_DIR
    fi
    cp -fr $BUILD_MAKE_DIR $BUILD_WWW_DIR

    php $DRUSH_PATH @$SITE_ALIAS.$BASE_ENV sql-dump --structure-tables-list="cache,cache_*,history,search_*,sessions,watchdog" > $BUILD_DIR/$BASE_ENV.sql
    wait
    echo "Import the database"
    mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf -e "DROP DATABASE $DB_NAME;"
    mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf -e "CREATE DATABASE $DB_NAME;"
    mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf $DB_NAME < $BUILD_DIR/$BASE_ENV.sql
  else
    echo "Run drush make. This can take upwards of 15 minutes."
    # Run our build.
    php $DRUSH_PATH make --working-copy $BUILD_DISTRO_DIR/$DISTRO-distro.make $BUILD_MAKE_DIR
  fi

  ELAPSED_TIME=$(($SECONDS - $START_TIME))
  echo "Make Time: " $(convertsecs $ELAPSED_TIME)
else
  # Start our timer.
  START_TIME=$SECONDS

  # Setup the acquia repo
  if [ ! -d "$ACQUIA_DIR" ]; then
    cd $BUILD_DIR;
    git clone $ACQUIA_GIT_URL acquia-repo
  fi

  echo "Pulling latest repository changes."
  cd $ACQUIA_DIR
  git pull
  # Branch names don't match environment names.
  BRANCH=$BASE_ENV
  if [ $BASE_ENV = 'test' ]; then
    BRANCH=stage
  elif [ $BASE_ENV = 'test2' ]; then
    BRANCH=stage2
  fi

  git checkout $BRANCH

  echo "Copying the files to the installation directory."
  cp -R $ACQUIA_DIR/docroot/ $BUILD_WWW_DIR

  if [ $REFRESH = true ]; then
    echo "Dump the database. This can take upwards of 15 minutes."
    php $DRUSH_PATH @$SITE_ALIAS.$BASE_ENV sql-dump --structure-tables-list="cache,cache_*,history,search_*,sessions,watchdog" > $BUILD_DIR/$BASE_ENV.sql

    echo "Import the database"
    mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf -e "DROP DATABASE $DB_NAME;"
    mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf -e "CREATE DATABASE $DB_NAME;"
    mysql --defaults-extra-file=$SCRIPT_DIR/conf/global-db.conf $DB_NAME < $BUILD_DIR/$BASE_ENV.sql
  fi
fi

if [ -d "$BUILD_WWW_DIR" ]; then
  echo "Set up sites directory"
  SITES_DIR=$BUILD_WWW_DIR/gsb_public/sites/default
  sudo rm -Rf $SITES_DIR
  sudo cp -R $SCRIPT_DIR/assets/$DISTRO/default $SITES_DIR
  ln -s $SITES_DIR $BUILD_WWW_DIR/gsb_public/sites/gsb

  # Give 777 permissions to sites directory.
  sudo chmod -R 777 $SITES_DIR

  # replace database credentials
  if [[ $platform == 'linux' ]]; then
    sed -i "s/---db-username---/$DB_USERNAME/g" $SITES_DIR/settings.php
    sed -i "s/---db-password---/$DB_PASS/g" $SITES_DIR/settings.php
    sed -i "s/---db-name---/$DB_NAME/g" $SITES_DIR/settings.php
    sed -i "s/---db-url---/$DB_URL/g" $SITES_DIR/settings.php
    sed -i "s/---db-port---/$DB_PORT/g" $SITES_DIR/settings.php
  elif [[ $platform == 'macos' ]]; then
    sed -i .bk "s/---db-username---/$DB_USERNAME/g" $SITES_DIR/settings.php
    sed -i .bk "s/---db-password---/$DB_PASS/g" $SITES_DIR/settings.php
    sed -i .bk "s/---db-name---/$DB_NAME/g" $SITES_DIR/settings.php
    sed -i .bk "s/---db-url---/$DB_URL/g" $SITES_DIR/settings.php
    sed -i .bk "s/---db-port---/$DB_PORT/g" $SITES_DIR/settings.php
fi

  sudo cp $SCRIPT_DIR/assets/.htaccess $BUILD_WWW_DIR/gsb_public/.htaccess
  cd $BUILD_WWW_DIR/gsb_public
  echo "Set site variables"
  php $DRUSH_PATH upwd --password=admin admin
  php $DRUSH_PATH vset file_temporary_path $BUILD_TMP_DIR
  php $DRUSH_PATH vset cache 0
  php $DRUSH_PATH vset preprocess_css 0
  php $DRUSH_PATH vset preprocess_js 0
  php $DRUSH_PATH vset error_level 2

  php -r "print json_encode(array('api_key'=> '$KRAKEN_KEY', 'api_secret'=> '$KRAKEN_SECRET'));"  | drush vset --format=json kraken -

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
  php -r "print json_encode(array('api_key'=> '$KRAKEN_KEY', 'api_secret'=> '$KRAKEN_SECRET'));"  | drush vset --format=json kraken -

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

#  ln -s ../build/www/gsb_public/profiles/gsb_public gsb_public

else
  echo "For some reason the installation directory wasn't created."
fi

