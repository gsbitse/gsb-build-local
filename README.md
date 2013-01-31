gsb-build-local
===============

Contains scripts used to build GSB sites locally.  

Instructions for using the build.sh script
============================================

1. Create a local directory - mkdir gsb
2. Copy build.sh to this new directory
3. Clone the gsb-distro into this new directory - git clone https://github.com/gsbitse/gsb-distro.git
4. Run the build script - sh build.sh

The directory structure should look like this:

/gsb
  build.sh
  gsb-distro
  
and after running the build script the directory should look something like this:

/gsb
  build.sh
  gsb-distro
  gsb_public
  
gsb_public contains your new drupal site with the typical docroot directory.

