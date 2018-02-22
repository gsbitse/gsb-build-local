#!/bin/bash
convertsecs() {
    m=$(( $1  % 3600 / 60 ))
    s=$(( $1 % 60 ))
    printf "%02d:%02d\n" $m $s
}

# Probably don't need to change these.
DISTRO=gsb-public # Distrobution to use.
DISTRO_GIT_URL=git@github.com:$DISTRO/$DISTRO-distro.git # Git url to the distro repo
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROD_TMP=/mnt/tmp/gsbpublic

# Get global variables
if [ -e $SCRIPT_DIR/global.cfg ]; then
  source $SCRIPT_DIR/global.cfg
else
  echo "[Build] $SCRIPT_DIR/global.cfg not found."
fi

# Get Operating System
unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
   platform='linux'
elif [[ "$unamestr" == 'FreeBSD' ]]; then
   platform='freebsd'
else
  platform='macos'
fi

# Check for missing variables.
ERROR=false
if [ -z $DRUSH_PATH ]; then
  echo "The \$DRUSH_PATH variable needs to be set."
  ERROR=true
fi

if [ -z $WWW_DIR ]; then
  echo "The \$WWW_DIR variable needs to be set."
  ERROR=true
fi

if [ -z $TMP_DIR ]; then
  echo "The \$TMP_DIR variable needs to be set."
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

# Location of where we put the build artifacts.
BUILD_DIR=$TMP_DIR/gsb-build-local/$DISTRO
DISTRO_DIR=$BUILD_DIR/$DISTRO-distro

# Create build directory if it doesn't exist.
if [ ! -d "$TMP_DIR/gsb-build-local" ]; then
  mkdir "$TMP_DIR/gsb-build-local"
fi

# Create build directory if it doesn't exist.
if [ ! -d "$BUILD_DIR" ]; then
  mkdir "$BUILD_DIR"
fi

# Read the default directory and profile name.
read -e -p "Enter the installation folder which will also be the db name. Don't use spaces! [$DEFAULT_INSTALL_DIR_NAME]: " INSTALL_DIR_NAME

# If nothing is specified then use the specified default.
if [ ! -n "$INSTALL_DIR_NAME" ]; then
  INSTALL_DIR_NAME=$DEFAULT_INSTALL_DIR_NAME
fi

# Acquia specific values
SITE_ALIAS=gsbpublic # Site alias used for drushing into acquia.
ACQUIA_DIR=$BUILD_DIR/acquia-repo # Location to put the Acquia git checkout.
ACQUIA_GIT_URL=$SITE_ALIAS@svn-3224.prod.hosting.acquia.com:$SITE_ALIAS.git  # URL to the acquia repo

# Set some default values.
INSTALL_DIR=$WWW_DIR/$INSTALL_DIR_NAME
DB_NAME=$INSTALL_DIR_NAME
SITE_TMP_DIR=$TMP_DIR/$INSTALL_DIR_NAME

# Create site temp directory if it doesn't exist.
if [ ! -d "$SITE_TMP_DIR" ]; then
  mkdir "$SITE_TMP_DIR"
fi

# Make sure something didn't go wrong and the install directory is the same as
# www. Otherwise we will delete the entire www directory.
if [[ $INSTALL_DIR = "$WWW_DIR/" ]]; then
  echo "Installation directory is the same as www dir and that is bad."
  exit
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
sudo rm -Rf $INSTALL_DIR

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
  if [ ! -d "$DISTRO_DIR" ]; then
    cd $BUILD_DIR
    git clone $DISTRO_GIT_URL
  fi

  # Checkout chosen branch.
  cd $DISTRO_DIR
  git pull
  git checkout $BRANCH

  # Move into our apache root and run drush make and/or replace the db.
  cd $WWW_DIR
  if [ $REFRESH = true ]; then
    echo "Run drush make and dump the database. This can take upwards of 15 minutes."
    php $DRUSH_PATH make --working-copy $DISTRO_DIR/$DISTRO-distro.make $INSTALL_DIR
    php $DRUSH_PATH @$SITE_ALIAS.$BASE_ENV sql-dump --structure-tables-list="cache,cache_*,history,search_*,sessions,watchdog" > $BUILD_DIR/$BASE_ENV.sql
    wait

    echo "Import the database"
    mysql --defaults-extra-file=$SCRIPT_DIR/global-db.cnf -e "DROP DATABASE $DB_NAME;"
    mysql --defaults-extra-file=$SCRIPT_DIR/global-db.cnf -e "CREATE DATABASE $DB_NAME;"
    mysql --defaults-extra-file=$SCRIPT_DIR/global-db.cnf $DB_NAME < $BUILD_DIR/$BASE_ENV.sql
  else
    echo "Run drush make. This can take upwards of 15 minutes."
    # Run our build.
    php $DRUSH_PATH make --working-copy $DISTRO_DIR/$DISTRO-distro.make $INSTALL_DIR
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
  cp -R $ACQUIA_DIR/docroot/ $INSTALL_DIR

  if [ $REFRESH = true ]; then
    echo "Dump the database. This can take upwards of 15 minutes."
    php $DRUSH_PATH @$SITE_ALIAS.$BASE_ENV sql-dump --structure-tables-list="cache,cache_*,history,search_*,sessions,watchdog" > $BUILD_DIR/$BASE_ENV.sql

    echo "Import the database"
    mysql -u$DB_USERNAME -p$DB_PASS -e "DROP DATABASE $DB_NAME;"
    mysql -u$DB_USERNAME -p$DB_PASS -e "CREATE DATABASE $DB_NAME;"
    mysql -u$DB_USERNAME -p$DB_PASS $DB_NAME < $BUILD_DIR/$BASE_ENV.sql
  fi
fi

# if [ -d "$SITES_DIR/.idea" ]; then
#  echo "Saving PHPStorm settings"
#  sudo cp $SITES_DIR/.idea $INSTALL_DIR
#fi

if [ -d "$INSTALL_DIR" ]; then
  echo "Set up sites directory"
  SITES_DIR=$INSTALL_DIR/sites/default
  sudo rm -Rf $SITES_DIR
  sudo cp -R $SCRIPT_DIR/assets/$DISTRO/default $SITES_DIR
  sudo cp $SCRIPT_DIR/extras/.htaccess-local $INSTALL_DIR/.htaccess

  echo "symlink $SITES_DIR $INSTALL_DIR/sites/gsb"
  ln -s $SITES_DIR $INSTALL_DIR/sites/gsb

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
  cd $INSTALL_DIR

  echo "Set site variables"
  php $DRUSH_PATH upwd --password=admin admin
  php $DRUSH_PATH vset file_temporary_path $TMP_DIR
  php $DRUSH_PATH vset cache 0
  php $DRUSH_PATH vset preprocess_css 0
  php $DRUSH_PATH vset preprocess_js 0
  php $DRUSH_PATH vset error_level 2

  #echo "Enable Kraken configuration"
  #php -r "print json_encode(array('api_key'=> $KRAKEN_KEY, 'api_secret'=> $KRAKEN_SECRET));"  | drush vset --format=json kraken -

  echo "Disable Memcache, Acquia and Shield"
  php $DRUSH_PATH dis -y memcache_admin acquia_purge acquia_agent shield

  echo "Run database updates"
  php $DRUSH_PATH updb -y

  echo "Revert features"
  php $DRUSH_PATH fra -y

  #echo "Enable Stage File Proxy and Devel"
  php $DRUSH_PATH en -y devel stage_file_proxy
  php $DRUSH_PATH vset stage_file_proxy_origin $REMOTE_URL

  echo "Enable views development setup."
  php $DRUSH_PATH vd
  php $DRUSH_PATH cc all

  ELAPSED_TIME=$(($SECONDS - $START_TIME))
  echo "Total Time: " $(convertsecs $ELAPSED_TIME)

  # Send a notification saying we are done.
  echo "The build has completed successfully."
  
  cd $INSTALL_DIR
  echo "release built is: " $BRANCH > gsb_build_options.txt
  echo "base env is: " $BASE_ENV >> gsb_build_options.txt
  echo "db refresh is: " $REFRESH >> gsb_build_options.txt
  echo "use make is: " $USE_MAKE >> gsb_build_options.txt  
  
else
  echo "The for some reason the installation directory wasn't created."
fi

