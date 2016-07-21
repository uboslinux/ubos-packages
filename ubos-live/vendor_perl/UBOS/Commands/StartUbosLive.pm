#!/usr/bin/perl
#
# Command that starts the UBOS Live service
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
# along with ubos-live.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Commands::StartUbosLive;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::AnyBackup;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

my $OPENVPN_CLIENT_CONFIG = '/etc/openvpn/ubos-live.conf';
my $CONF_DIR              = '/etc/ubos-live';
my $OPENVPN_CLIENT_KEY    = $CONF_DIR . '/client.key';
my $OPENVPN_CLIENT_CSR    = $CONF_DIR . '/client.csr';
my $OPENVPN_CLIENT_CRT    = $CONF_DIR . '/client.crt';

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
    my $token         = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile,
            'token=s'      => \$token );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    _ensureOpenvpnKeyCsr();
    _ensureRegistered( $token );
    _ensureOpenvpnClientConfig();

    UBOS::Utils::myexec( 'systemctl start openvpn@ubos-live.service' );
    UBOS::Utils::myexec( 'systemctl enable openvpn@ubos-live.service' );

    return 1;
}

##
# Ensure that there is an OpenVPN client key and csr
sub _ensureOpenvpnKeyCsr {
    unless( -e $OPENVPN_CLIENT_KEY ) {
        UBOS::Utils::myexec( "openssl genrsa -out '$OPENVPN_CLIENT_KEY' 4096" );
    }
    unless( -e $OPENVPN_CLIENT_KEY ) {
        fatal( 'Failed to generate UBOS Live client VPN key' );
    }
    chmod 0600, $OPENVPN_CLIENT_KEY;

    unless( -e $OPENVPN_CLIENT_CSR ) {
        my $id = UBOS::Host::gpgHostKeyFingerprint();
        $id = lc( $id );
        UBOS::Utils::myexec( "openssl req -new -key '$OPENVPN_CLIENT_KEY' -out '$OPENVPN_CLIENT_CSR' -subj '/CN=$id.ubos-live.indiecomp.com'" );
    }
    unless( -e $OPENVPN_CLIENT_CSR ) {
        fatal( 'Failed to generate UBOS Live client VPN certificate request' );
    }
}

##
# Ensure that the device is registered and has the appropriate key
# $token: the registration token entered by the user
sub _ensureRegistered {
    my $token = shift || '';

    unless( -e $OPENVPN_CLIENT_CRT ) {
        while( $token !~ m!^\s*[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}\s*$! ) {
            print "Enter the token you obtained to register (looks like XXXX-XXXX):\n";
            $token = <STDIN>;
        }
print "*** Simulated: generate cert from this CSR, put into $OPENVPN_CLIENT_CRT and hit return\n";
print UBOS::Utils::slurpFile( $OPENVPN_CLIENT_CSR );
my $ret = <STDIN>;
    }
    unless( -e $OPENVPN_CLIENT_CRT ) {
        fatal( 'Failed to register with UBOS Live.' );
    }
}

##
# Ensure that the OpenVPN client is set up correctly
sub _ensureOpenvpnClientConfig {
    unless( -e $OPENVPN_CLIENT_CONFIG ) {
        UBOS::Utils::saveFile( $OPENVPN_CLIENT_CONFIG, <<CONTENT );
#
# OpenVPN UBOS Live client-side config file.
# Adopted from OpenVPN client.conf example
# DO NOT MODIFY. UBOS WILL OVERWRITE MERCILESSLY.
#
client
dev tun99
tun-ipv6
proto udp
remote openvpn-ubos-live.indiecomp.com 1194
resolv-retry infinite
nobind
user nobody
group nobody
persist-key
persist-tun
;mute-replay-warnings
ca $CONF_DIR/ca.indiecomp.com.crt
cert $OPENVPN_CLIENT_CRT
key $OPENVPN_CLIENT_KEY
;remote-cert-tls server
;tls-auth ta.key 1
comp-lzo
verb 3
;mute 20
CONTENT
    }
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--token <token>]
SSS
    Start the UBOS Live service for this device.
    Specify <token> on initial setup.
HHH
    };
}

1;
