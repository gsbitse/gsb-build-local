gsb-build-local
===============

Contains scripts used to build GSB sites locally.  

## gsb-public-build.sh

### Instructions

1. Create a .gsb-local-build folder in your root directory. - mkdir .gsb-build-local
2. Into that directory copy global.cfg.example and rename it global.cfg
3. Set the values in global.cfg according to your environment.
4. Run sh gsb-public-build.sh

### Hints

* Create a tmp directory in the same directory you place your other sites. Give it 777 permissions. Use this for the TMP_DIR variable.
* Make sure wherever you build the site you have the directory set up in apache.

