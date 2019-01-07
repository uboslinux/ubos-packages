#!/usr/bin/perl
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

use AmazonSes;
use UBOS::Utils;

if( 'deploy' eq $operation ) {
    AmazonSes::generatePostfixFileFragment( $config );

    # Moved from package install
    UBOS::Utils::myexec( "postalias /etc/postfix/ubos-aliases" );
}
if( 'undeploy' eq $operation ) {
    AmazonSes::removePostfixFileFragment( $config );
}
AmazonSes::regeneratePostfixFilesAndRestart();

1;
