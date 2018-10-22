#!/usr/bin/perl
#
# This callback updates Pagekite when a virtual hostname has been added or removed
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::HostnameCallbacks::UpdatePagekite;

use UBOS::Pagekite::Pagekite;

##
# A site is deploying to this host
# $site: the Site
sub siteDeploying {
    my $site = shift;

    # We do this here so that pagekite is active by the time we provision
    # a letsencrypt certificate, which is before the site is fully deployed.
    # At this time, the site is not in UBOS::Host::sites() yet.

    my $siteId = $site->siteId();
    my $sites  = UBOS::Host::sites();

    unless( exists( $sites->{$siteId} )) {
        $sites->{$siteId} = $site;
    }

    return UBOS::Pagekite::Pagekite::deployedSitesUpdated( $sites );
}

##
# A site has been deployed to this host
# $site: the Site
sub siteDeployed {
    my $site = shift;

    # noop
}

##
# A site is undeploying from this host
# $site: the Site
sub siteUndeploying {
    my $site = shift;

    # noop
}
##
# A site has been undeployed from this host
# $site: the Site
sub siteUndeployed {
    my $site = shift;

    my $sites = UBOS::Host::sites();
    return UBOS::Pagekite::Pagekite::deployedSitesUpdated( $sites );
}

1;
