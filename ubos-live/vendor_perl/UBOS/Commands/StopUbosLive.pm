#!/usr/bin/perl
#
# Command that stops the UBOS Live service
#
# This file is part of ubos-live.
# (C) 2012-2016 Indie Computing Corp.
#
# ubos-live is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-live is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Commands::StopUbosLive;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::AnyBackup;
use UBOS::Host;
use UBOS::Logging;
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

    my $verbose       = 0;
    my $logConfigFile = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    UBOS::Utils::myexec( 'systemctl disable openvpn@ubos-live.service' );
    UBOS::Utils::myexec( 'systemctl stop openvpn@ubos-live.service' );

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH
    [--verbose | --logConfig <file>]
SSS
    Stop the UBOS Live service for this device.
HHH
    };
}

1;
