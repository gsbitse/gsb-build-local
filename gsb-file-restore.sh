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

# Location of where we put the build artifacts.
# gsb-public-build.sh       # SCRIPT_DIR
#  -> build                 # BUILD_DIR
#     -> gsb-public-distro  # BUILD_DISTRO_DIR
#     -> www                # BUILD_WWW_DIR
#     -> tmp                # BUILD_TMP_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR=$SCRIPT_DIR/build
BUILD_MAKE_DIR=$BUILD_DIR/gsb_public
BUILD_WWW_DIR=$BUILD_DIR/www

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

# If anything is missing then exit.
if [ $ERROR = true ]; then
  exit
fi

# Remove the old installation directory
sudo rm -Rf $BUILD_WWW_DIR

# Start our counter.
START_TIME=$SECONDS

# Move into our apache root and run drush make and/or replace the db.
if [ $REFRESH = true ]; then
  echo "BUILD Copy make files to apache folder"
  if [ ! -d "$BUILD_WWW_DIR" ]; then
    echo "Creating $BUILD_WWW_DIR"
    mkdir -p $BUILD_WWW_DIR
  fi
  cp -fr $BUILD_MAKE_DIR $BUILD_WWW_DIR

  ELAPSED_TIME=$(($SECONDS - $START_TIME))
  echo "Make Time: " $(convertsecs $ELAPSED_TIME)
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

  echo "Revert features"
  php $DRUSH_PATH fra -y

  echo "Clear Cache."
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