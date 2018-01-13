#!/usr/bin/perl
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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
