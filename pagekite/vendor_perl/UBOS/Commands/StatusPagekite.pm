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

    print 'Status:        ' . ( $status->{active} eq 'active' ?  'active' : 'inactive' ) . "\n";
    print 'Enabled kites: ' . ( $status->{allKites} ? '<all sites>' : join( ' ', @{$status->{activeKites}} )) : "\n";
    print 'Active kites:  ' . join( ' ', @{$status->{enabledKites}} ) . "\n";

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

