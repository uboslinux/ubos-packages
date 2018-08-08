#!/usr/bin/perl
#
# Command that shows the status of the UBOS Pagekite service
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::StatusPagekite;

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

    my $verbose         = 0;
    my $logConfigFile   = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $status = UBOS::Pagekite::Pagekite::status();

    if( exists( $status->{status} ) && $status->{status} eq 'active' ) {
        print "Status:         active\n";
    } else {
        print "Status:         inactive\n";
    }
    if( exists( $status->{allKites} ) && $status->{allKites} ) {
        print "Active kites:   <for all sites>\n";
    } elsif( exists( $status->{activeKites} ) && @{$status->{activeKites}} ) {
        print 'Active kites:   ' . join( ' ', @{$status->{activeKites}} ) . "\n";
    } else {
        print "Active kites:   <none>\n";
    }
    if( exists( $status->{enabledKites} ) && @{$status->{enabledKites}} ) {
        print 'Enabled kites:  ' . join( ' ', @{$status->{enabledKites}} ) . "\n";
    } else {
        print "Enabled kites:  <none>\n";
    }
    if( $verbose ) {
        my $sites = UBOS::Host::sites();
        if( keys %$sites ) {
            print 'Deployed sites: ' . join( ' ', sort map{ $_->hostname() } values %$sites ) . "\n";
        } else {
            print "Deployed sites: <none>\n";
        }

        if( UBOS::Pagekite::Pagekite::isDaemonRunning()) {
            print "Daemon running: yes\n";
        } else {
            print "Daemon running: no\n";
        }
    }
    return 0;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Show the status of the Pagekite service for this device.
SSS
        'cmds' => {
            '' => <<HHH,
    Show status and print the active kites
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

