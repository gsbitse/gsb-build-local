#!/bin/bash

# Note: To run this script you'll need to clone the distro
# git clone https://github.com/gsbitse/gsb-distro.git

# Read the profile name to use.
read -e -p "Enter the profile name [gsb_public]: " PROFILE

# If nothing is specified then use gsb_public
if [ ! -n "$PROFILE" ]; then
  PROFILE=gsb_public
fi

# Set some default values.
WWWDIR=~/Sites/gsb
INSTALLDIR=$WWWDIR/$PROFILE
DISTRODIR=$WWWDIR/gsb-distro

# Set the files directory
FILESDIR=$INSTALLDIR/sites/default/files

# Set some default database values
DB_USERNAME=root
DB_PASS=
DB_URL=localhost
DB_PORT=3306

# Remove the old installation directory
sudo rm -Rf $INSTALLDIR

# Build our new build.
~/drush/drush make $DISTRODIR/${PROFILE//_/-}-distro.make $INSTALLDIR

# Make the files and private directory
mkdir $FILESDIR
mkdir $FILESDIR/private

# Give 777 permissions to files.
chmod -R 777 $FILESDIR

# Move into the install directory and install our installation profile.
cd $INSTALLDIR
~/drush/drush si -y --db-url="mysql://$DB_USERNAME:@$DB_URL:$DB_PORT/$PROFILE" --site-name="revamp" $PROFILE

# Fix the files directory again for the new directories that were created.
chmod -R 777 $FILESDIR

# Launch our site in a new tab in firefox.
#firefox -new-tab localhost/$DISTRO

# Send a notification saying we are done.
say "The build has completed successfully."

