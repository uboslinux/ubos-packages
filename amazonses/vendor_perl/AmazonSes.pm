#!/usr/bin/perl
#
# Collects code to configure postfix for Amazon SES.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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
my $sesPort  = 587; # 25 is blocked by many ISPs. STARTTLS not wrappermode

##
# Regenerate the postfix config files from the fragments deposited into
# the fragment directories, and restart postfix
sub regeneratePostfixFilesAndRestart {
    _regenerateFile( $mapFile,  $mapDir );
    _regenerateFile( $saslFile, $saslDir );

    UBOS::Utils::myexec( "systemctl restart postfix" );
}

sub _regenerateFile {
    my $dest = shift;
    my $dir  = shift;

    my $content = '';

    my $dirFh;
    opendir $dirFh, $dir;
    my @files = readdir $dirFh;
    closedir $dirFh;

    @files = grep { ! m!^\.\.?$!  } @files;
    foreach my $file ( sort @files ) {
        $content .= UBOS::Utils::slurpFile( "$dir/$file" );
    }
    UBOS::Utils::saveFile( $dest, $content, 0600, 'postfix', 'postfix' ); # may contain SES credentials
}

##
# Generate a fragment file for a particular site
# $config: config object passed into the AppConfigurationItem perlscript
sub generatePostfixFileFragment {
    my $config = shift;

    my $siteId = $config->getResolve( 'site.siteid' );

    my $accessKeyId   = $config->getResolve( 'installable.customizationpoints.aws_access_key_id.value' );
    my $secretKey     = $config->getResolve( 'installable.customizationpoints.aws_secret_key.value' );
    my $domainsString = $config->getResolveOrNull( 'installable.customizationpoints.domains.value', undef, 1 ); # currently not supported
    my $mailServer    = $config->getResolve( 'installable.customizationpoints.ses_mail_server.value' );

    $accessKeyId   =~ s/^\s+//g;
    $accessKeyId   =~ s/\s+$//g;
    $secretKey     =~ s/^\s+//g;
    $secretKey     =~ s/\s+$//g;
    $mailServer    =~ s/^\s+//g;
    $mailServer    =~ s/\s+$//g;

    my @domains = ();
    if( defined( $domainsString )) {
        $domainsString =~ s/^\s+//g;
        $domainsString =~ s/\s+$//g;

        @domains = split /\s+/, $domainsString;
    }

    unless( @domains ) {
        @domains = ( $config->getResolve( 'site.hostname' )); # defaults to site hostname
    }

    my $mapNewContent  = '';
    my $saslNewContent = '';

    foreach my $domain ( @domains ) {
        my $escapedDomain = $domain;
        $escapedDomain =~ s/\./\\./g;

        $mapNewContent .= <<CONTENT;
/.*\@$escapedDomain/ [$mailServer]:$sesPort
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
sub removePostfixFileFragment {
    my $config = shift;

    my $siteId = $config->getResolve( 'site.siteid' );

    UBOS::Utils::deleteFile( "$mapDir/$siteId" );
    UBOS::Utils::deleteFile( "$saslDir/$siteId" );
}

1;
