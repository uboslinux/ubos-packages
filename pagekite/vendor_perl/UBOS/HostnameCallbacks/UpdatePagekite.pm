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
# A site has been deployed to this host
# $siteId: the id of the site
# $hostname: the hostname of the site
# @nics: the network interfaces on which the site can be reached
sub deployed {
    my $siteId   = shift;
    my $hostname = shift;
    my @nics     = @_;

    return UBOS::Pagekite::Pagekite::deployedSitesUpdated();
}

##
# A site has been undeployed from this host
# $siteId: the id of the site
# $hostname: the hostname of the site
# @nics: the network interfaces on which the site can be reached
sub undeployed {
    my $siteId   = shift;
    my $hostname = shift;
    my @nics     = @_;

    return UBOS::Pagekite::Pagekite::deployedSitesUpdated();
}

1;
