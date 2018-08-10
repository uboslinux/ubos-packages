#!/usr/bin/perl
#
# The Pagekite service as integrated into UBOS.
#
# There are two modes:
# 1) a list of site names has been given; we run pagekite for those if
#    and only if a given site exists. So we may run pagekite for any
#    number of sites from 0 to the length of the list given.
# 2) we run pagekite for all sites that are not Tor sites.
# As there may or may not be any sites on the device for which we run
# kites, we may or may not run the pagekite.service systemd service.
#
# The status file keeps track.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Pagekite::Pagekite;

use UBOS::Logging;
use UBOS::Host;
use UBOS::Utils;

my $systemdService = 'pagekite.service';
my $statusFile     = '/etc/pagekite.status';
my $secretFile     = '/etc/pagekite.d/10_secret.rc';
my $kiteFile       = '/etc/pagekite.d/80_sites.rc';

my $_status = undef; # read as needed

##
# Activate Pagekite.
# $namedKitesP: array of names of kites to activate
# $allKites: if true, activate all sites as kites
# $kiteSecret: any provided kite secret
# return: desired exit code
sub activate {
    my $namedKitesP = shift;
    my $allKites    = shift; 
    my $kiteSecret  = shift;

    trace( 'Pagekite::activate: all:', $allKites, 'named:', @$namedKitesP );

    if( $kiteSecret ) {
        UBOS::Utils::saveFile( $secretFile, <<CONTENT, 0600 );
kitesecret = $kiteSecret
CONTENT
    }
    unless( -e $secretFile ) {
        fatal( 'No kite secret provided. On the first invocation, specify --kitesecret <secret>.' );
    }
    my $status = status();
    
    my @enabledKites = ();
    if( @$namedKitesP ) {
        # we rely on them being sorted
        @enabledKites = sort @$namedKitesP;

        $status->{enabledKites} = \@enabledKites;
        $status->{allKites}     = $allKites;

    } elsif( exists( $status->{enabledKites} )) {
        @enabledKites = @{$status->{enabledKites}};
        if( $allKites ) {
            fatal( 'Do not specify --all when not providing any kite names.' );
        }
    }
    unless( @enabledKites ) {
        fatal( 'No kite names provided. Specify at least one kite name.' );
    }

    my @activeKites = determineActiveKiteNames( \@enabledKites, $allKites );

    $status->{status} = 'active';
    $status->{activeKites} = \@activeKites,

    updateStatus( $status );

    generateKiteConfig( \@activeKites );
    my $ret = activateDeactivateRestartSystemdService( [], \@activeKites );
    return $ret;
}

##
# Deactivate Pagekite. If not active, do nothing.
# return: desired exit code
sub deactivate {

    trace( 'Pagekite::deactivate' );

    my $status = status();

    generateKiteConfig( [] );
    my $ret = activateDeactivateRestartSystemdService( $status->{activeKites}, [] );

    my $newStatus = {
        'status'       => 'inactive',
        'enabledKites' => [],
        'activeKites'  => [],
        'allKites'     => 0
    };
    updateStatus( $newStatus );

    return $ret;
}

##
# Determine the current status JSON
# return: the status JSON
sub status {

    unless( $_status ) {
        if( -e $statusFile ) {
            $_status = UBOS::Utils::readJsonFromFile( $statusFile );
        } else {
            $_status = {};
        }
    }
    return $_status;
}

##
# Set a new status
# $newStatus the status json
sub updateStatus {
    my $newStatus = shift;

    trace( 'Pagekite::updateStatus', $newStatus );

    $_status = $newStatus;
    UBOS::Utils::writeJsonToFile( $statusFile, $_status );
}

##
# Is Pagekite currently active?
# return: true or false;
sub isActive {

    my $status = status();

    if( exists( $status->{status} ) && 'active' eq $status->{status} ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Determine whether the pagekite daemon is currently running
# return: true or false
sub isDaemonRunning {

    my $out;
    if( UBOS::Utils::myexec( 'systemctl status ' . $systemdService, undef, \$out, \$out ) == 0 ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Generate, or regenerate, the Pagekite config file fragment
# $kiteNamesP: names of the kites that shall be active
sub generateKiteConfig {
    my $kiteNamesP = shift;

    trace( 'Pagekite::generateKiteConfig', @$kiteNamesP );

    my $content = <<CONTENT;
# Automatically generated by UBOS package pagekite.
# Manual changes will be overwritten mercilessly.
# If you don't want this, uninstall UBOS package pagekite.

CONTENT
    if( @$kiteNamesP ) {
        foreach my $name ( @$kiteNamesP ) {
            my $site = UBOS::Host::findSiteByHostname( $name );

            $content .= <<CONTENT;
service_on = http:$name : localhost:80 : \@kitesecret
CONTENT
            if( $site && $site->hasTls()) {
                $content .= <<CONTENT;
service_on = https:$name : localhost:443 : \@kitesecret
CONTENT
             }
        }
    } else {
        $content .= <<CONTENT;
# Currently none
CONTENT
    }

    UBOS::Utils::saveFile( $kiteFile, $content, 0644 );
}

##
# Determine the to-be-active kite names given what is deployed on
# the device, and the arguments provided.
# $namedKitesP: array of names of kites to activate
# $allKites: if true, activate all sites as kites
# return: list of kite names
sub determineActiveKiteNames {
    my $namedKitesP = shift;
    my $allKites    = shift;

    my @ret;
    my $sites = UBOS::Host::sites();
    if( keys %$sites ) {
        if( $allKites || UBOS::Host::findSiteByHostname( '*' )) {
            @ret = sort map { $_->hostname() } values %$sites;
        } else {
            @ret = grep { UBOS::Host::findSiteByHostname( $_ ) } @$namedKitesP;
        }
    } else {
        @ret = ();
    }

    trace( 'Pagekite::determineActiveKiteNames: all:', $allKites, 'named:', @$namedKitesP, 'returns:', @ret );

    return @ret;
}

##
# Activate or deactivate the systemd service as needed
# $oldKiteNamesP: old array of names of the kites that were active until now
# $newKiteNamesP: new array of names of the kites that shall be active
sub activateDeactivateRestartSystemdService {
    my $oldKiteNamesP = shift;
    my $newKiteNamesP = shift;

    my $ret;
    my $out;
    if( !@$newKiteNamesP ) {
		trace( 'Pagekite::activateDeactivateRestartSystemdService: no new kite names' );

        $ret = UBOS::Utils::myexec( 'systemctl disable --now ' . $systemdService, undef, \$out, \$out );
        # might be disabled already; doesn't matter

    } elsif( isDaemonRunning() ) {
        # running already -- determine whether we need to restart
        # we assume there are no duplicates, and they are sorted (see activate())
        my $doRestart;
        if( @$oldKiteNamesP == @$newKiteNamesP ) {
            for( my $i=0 ; $i<@$oldKiteNamesP ; ++$i ) {
                if( $oldKiteNamesP->[$i] ne $newKiteNamesP->[$i] ) {
                    $doRestart = 1;
                    last;
                }
            }
        } else {
            $doRestart = 1;
        }

        if( $doRestart ) {
            trace( 'Pagekite::activateDeactivateRestartSystemdService: restarting daemon' );
            $ret = UBOS::Utils::myexec( 'systemctl restart ' . $systemdService, undef, \$out, \$out );
        } else {
            trace( 'Pagekite::activateDeactivateRestartSystemdService: no need to restart daemon' );
            $ret = 0;
        }

    } else {
        # not running
        trace( 'Pagekite::activateDeactivateRestartSystemdService: starting daemon' );
        $ret = UBOS::Utils::myexec( 'systemctl enable --now ' . $systemdService, undef, \$out, \$out );
    }
    return $ret;
}

##
# Callback: the list of sites deployed on this host has changed
sub deployedSitesUpdated {

    trace( 'Pagekite::deployedSitesUpdated' );

    if( isActive() ) {
        my $status        = status();
        my $enabledKitesP = $status->{enabledKites};
        my $allKites      = $status->{allKites};

        my @activeKites = determineActiveKiteNames( $enabledKitesP, $allKites );
        generateKiteConfig( \@activeKites );
        activateDeactivateRestartSystemdService( $status->{activeKites}, \@activeKites );

        $status->{activeKites} = \@activeKites;
        updateStatus( $status );
    }

    return 1;
}

1;
