#!/usr/bin/perl
#
# Command that starts the UBOS Pagekite service
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::StartPagekite;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Logging;
use UBOS::Pagekite::Pagekite;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" );
    }

    my $verbose         = 0;
    my $logConfigFile   = undef;
    my $all             = 0;
    my $kiteSecret      = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile,
            'all'          => \$all,
            'kitesecret=s' => \$kiteSecret );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my %namedKites = (); # To check for duplicates
    foreach my $arg ( @args ) {
        if( exists( $namedKites{$arg} )) {
            fatal( 'Kite name provided more than once:', $arg );
        }
        $namedKites{$arg} = 1;
    }

    if( UBOS::Pagekite::Pagekite::isActive() ) {
        fatal( 'Pagekite is active already.' );
    }

    my $ret = UBOS::Pagekite::Pagekite::activate( [ keys %namedKites ], $all, $kiteSecret );
    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Start the Pagekite service for this device.
SSS
        'details' => <<SSS,
    This will only work if you have provisioned the needed kites on the
    pagekite.net website.
SSS
        'cmds' => {
            <<SSS => <<HHH,
    [--kitesecret <secret>][--all] <kite>...
SSS
    Start the Pagekite service for this device, activating the list of
    named kites. This will compare the list of kites with the deployed sites,
    and only activate those kites for which matching sites exist.
    On the first invocation, the kite secret <secret> found on your account at
    pagekite.net must be provided.
    If you specify --all, UBOS will automatically create additional kites
    for all other sites currently on the device, and all that you might
    create in the future. Without --all, UBOS will only create the
    specified kites
HHH
         },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH
    Use an alternate log configuration file for this command.
HHH
        }
    };
}

1;

