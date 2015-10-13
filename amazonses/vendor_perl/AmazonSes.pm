#!/usr/bin/perl
#
# Collects code to configure postfix for Amazon SES.
#
# This file is part of amazonses.
# (C) 2012-2015 Indie Computing Corp.
#
# amazonses is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# amazonses is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with amazonses.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package AmazonSes;

use UBOS::Logging;
use UBOS::Utils;

my $mapFile  = '/etc/amazonses/sender_dependent_relayhost_map';
my $saslFile = '/etc/amazonses/smtp_sasl_password_map';
my $mapDir   = '/etc/amazonses/sender_dependent_relayhost_map.d';
my $saslDir  = '/etc/amazonses/smtp_sasl_password_map.d';

##
# Regenerate the postfix config files from the fragments deposited into
# the fragment directories, and restart postfix
sub regeneratePostfixFilesAndRestart() {
    _regenerateFile( $mapFile,  $mapDir );
    _regenerateFile( $saslFile, $saslDir );

    UBOS::Utils::myexec( "systemctl restart postfix" );

}
sub _regenerateFile {
    my $dest = shift;
    my $dir  = shift;

    my $content = '';

    opendir my $dirFh, $dir;
    my @files = readdir $dirFh;
    closedir $dirFh;

    foreach my $file ( sort @files ) {
        $content .= UBOS::Utils::slurpFile( "$dir/$file" );
    }
    UBOS::saveFile( $dest, $content );
}

##
# Generate a fragment file for a particular site
# $config: config object passed into the AppConfigurationItem perlscript
sub generatePostfixFileFragment() {
    my $config = shift;

    my $siteId = $config->{site}->{siteId};

    my $accessKeyId   = $varMap->{installable}->{customizationpoints}->{AWSAccessKeyId}->{value};
    my $secretKey     = $varMap->{installable}->{customizationpoints}->{AWSSecretKey}->{value};
    my $domainsString = $varMap->{installable}->{customizationpoints}->{Domains}->{value};
    my $mailServer    = $varMap->{installable}->{customizationpoints}->{SesMailServer}->{value};

    $accessKeyId   =~ s/^\s+//g;
    $accessKeyId   =~ s/\s+$//g;
    $secretKey     =~ s/^\s+//g;
    $secretKey     =~ s/\s+$//g;
    $domainsString =~ s/^\s+//g;
    $domainsString =~ s/\s+$//g;
    $mailServer    =~ s/^\s+//g;
    $mailServer    =~ s/\s+$//g;

    my @domains = split /\s+/, @domainsString;
    unless( @domains ) {
        @domains = ( $config->{site}->{hostname} ); # defaults to site hostname
    }

    my $mapNewContent  = '';
    my $saslNewContent = '';

    foreach my $domain ( @domains ) {
        my $escapedDomain = $domain;
        $escapedDomain =~ s/\./\\./g;

        $mapNewContent .= <<CONTENT;
/.*\@$escapedDomain/ [$mailServer]:25
CONTENT

        $saslNewContent .= <<CONTENT;
/.*\@$escapedDomain/ $accessKeyId:$secretKey
CONTENT
    }

    UBOS::Utils::saveFile( "$mapDir/$siteId", $mapNewContent );
    UBOS::Utils::saveFile( "$saslDir/$siteId", $saslNewContent );
}

##
# Remove a fragment file for a particular site
# $config: config object passed into the AppConfigurationItem perlscript
sub removePostfixFileFragment() {
    my $config = shift;

    my $siteId = $config->{site}->{siteId};

    UBOS::Utils::deleteFile( "$mapDir/$siteId" );
    UBOS::Utils::deleteFile( "$saslDir/$siteId" );
}

1;
