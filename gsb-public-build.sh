#!/bin/bash
# Get global variables

if [ -e conf/global.cfg ]; then
  source conf/global.cfg
else
  echo "[Build] global.cfg not found."
fi

if [ -e conf/lastbranch.cfg ]; then
  source conf/lastbranch.cfg
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

source conf/functions.sh

# Check for missing variables.
ERROR=false
if [ -z $DRUSH_PATH ]; then
  echo "[Build] The \$DRUSH_PATH variable needs to be set."
  ERROR=true
fi

if [ -z $BUILD_WWW_DIR ]; then
  echo "[Build] The \$BUILD_WWW_DIR variable needs to be set."
  ERROR=true
fi

if [ -z $BUILD_TMP_DIR ]; then
  echo "[Build] The \$BUILD_TMP_DIR variable needs to be set."
  ERROR=true
fi

if [ -z $DB_USERNAME ]; then
  echo "[Build] The \$DB_USERNAME variable needs to be set."
  ERROR=true
fi

if [ -z $DB_PASS ]; then
  echo "[Build] The \$DB_PASS variable needs to be set."
  ERROR=true
fi

if [ ! -w "$PROD_TMP" ]; then
  echo "[Build] The temporary directory $PROD_TMP needs to exist and be writable."
  ERROR=true
fi

# If anything is missing then exit.
if [ $ERROR = true ]; then
  exit
fi

echo "-[Stanford GSB Public Website]----------------------------------------------"
if [ -d "src/gsb_public/profiles/gsb_public" ]; then
  cd src/gsb_public/profiles/gsb_public
  git remote update
  git status -uno
fi
echo "---[Build Options]----------------------------------------------------------";
echo "   [1] Full Build: Runs make and downloads fresh database from production"
echo "   [2] Quick Build: Restores files and database from last full build"
echo "   [3] Files: Restores files from last full build"
echo "   [4] Database: Restores database from last full build"
echo "   [5] Database: Copy database from production, keep files as are"
echo "   [6] Cancel"
read -e -p ":" BUILD_OPTION

if [ $BUILD_OPTION = 1 ]; then
  read -e -p "Enter the branch to use [$LAST_BRANCH]: " BRANCH
  # If nothing is specified then use the specified default.
  if [ ! -n "$BRANCH" ]; then
    BRANCH=$LAST_BRANCH
  else
    echo "LAST_BRANCH=$BRANCH" > conf/lastbranch.cfg
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
# Start our counter.
START_TIME=$SECONDS
if [ $BUILD_OPTION = 1 ]; then
  echo "---[Full Build]-----"
  get_gsb-public_distro
  run_drush_make
  configure_drupal_sites_dir
  export_db_from_acquia
  copy_make_files_to_www
  import_database
  post_database_operations
elif [ $BUILD_OPTION = 2 ]; then
  echo "---[Quick Build]-----"
  copy_make_files_to_www
  import_database
  post_database_operations
elif [ $BUILD_OPTION = 3 ]; then
  echo "--[Restore files from last build]-----"
  copy_make_files_to_www
elif [ $BUILD_OPTION = 4 ]; then
  echo "---[Restore database from last full build]-----"
  import_database
  post_database_operations
elif [ $BUILD_OPTION = 5 ]; then
  echo "---[Restore database from prod]-----"
  export_db_from_acquia
  import_database
  post_database_operations
elif [ $BUILD_OPTION = 6 ]; then
  echo "---[Goodbye]-----"
  exit
fi

cd $BUILD_WWW_DIR/gsb_public
php $DRUSH_PATH cc all
ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "[Build] Total Time: " $(convertsecs $ELAPSED_TIME)
echo "[Build]  The build has completed successfully."
