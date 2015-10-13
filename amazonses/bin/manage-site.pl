#!/usr/bin/perl
#

use strict;

use AmazonSes;
use UBOS::Utils;

if( 'deploy' eq $operation ) {
    AmazonSes::generatePostfixFileFragment( $config );
}
if( 'undeploy' eq $operation ) {
    AmazonSes::removePostfixFileFragment( $config );
}
AmazonSes::regeneratePostfixFilesAndRestart();

1;
