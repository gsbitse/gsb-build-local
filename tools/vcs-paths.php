<?php

$makefile = 'profiles/gsb_public/gsb_public.make';
$projects = array();
$profile_path = '$PROJECT_DIR$/src/gsb_public/profiles/gsb_public/';

$outData = drupal_parse_info_file($makefile);

//print_r($outData['projects']);
foreach ($outData['projects'] as $key => $project) {
    if ($project['subdir'] == 'contrib') {
        // Ignore
    } elseif ($project['subdir'] == 'custom' || $project['subdir'] == 'custom/features') {
        echo '<mapping directory="' . $profile_path .'modules/'. $project['subdir'] .'/'. $key . '" vcs="Git" />' . "\n";

    } elseif ($project['type'] == 'theme') {
        echo '<mapping directory="' . $profile_path . 'themes/' . $key . '" vcs="Git" />' . "\n";
    }
}