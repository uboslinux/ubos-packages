#!/usr/bin/perl
#
# Command that backs up data on this device to Amazon S3.
#
# This file is part of amazons3
# (C) 2012-2016 Indie Computing Corp.
#
# amazons3 is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# amazons3 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Commands::BackupToAmazonS3;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::BackupUtils;
use UBOS::Backup::ZipFileBackup;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

my $DEFAULT_CONFIG_FILE = '/etc/amazons3/aws-config-for-backup';
my $TMP_DIR             = '/var/tmp';
my %CONFIG_FIELDS       = (
    'aws_access_key_id'     => [ 'Amazon AWS access key id',     '[A-Z0-9]{20}' ],
    'aws_secret_access_key' => [ 'Amazon AWS secret access key', '[A-Za-z0-9/]{40}' ],
);
my $DEFAULT_REGION = 'us-east-1';
my $PROFILE_NAME   = 'backup';

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $configFile    = $DEFAULT_CONFIG_FILE;
    my @siteIds       = ();
    my @hostnames     = ();
    my @appConfigIds  = ();
    my $region        = undef;
    my $bucket        = undef;
    my $createBucket  = undef;
    my $name          = undef;
    my $noTls         = undef;
    my $encryptId     = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'config=s',     => \$configFile,
            'siteid=s'      => \@siteIds,
            'hostname=s'    => \@hostnames,
            'appconfigid=s' => \@appConfigIds,
            'region=s'      => \$region,
            'bucket=s'      => \$bucket,
            'createbucket'  => \$createBucket,
            'name=s'        => \$name,
            'notls'         => \$noTls,
            'encryptid=s'   => \$encryptId );

    UBOS::Logging::initialize( 'ubos-admin', 'backup-to-amazon-s3', $verbose, $logConfigFile );

    if(    !$parseOk
        || @args
        || ( $verbose && $logConfigFile )
        || ( !$name && ( @appConfigIds || ( @siteIds + @hostnames > 1 )))
        || ( @siteIds && @hostnames ))
    {
        fatal( 'Invalid invocation: backup', @_, '(add --help for help)' );
    }

    foreach my $host ( @hostnames ) {
        my $site = UBOS::Host::findSiteByHostname( $host );
        push @siteIds, $site->siteId;
    }

    my $hostId = lc( UBOS::Host::gpgHostKeyFingerprint());

    unless( $region ) {
        $region = $DEFAULT_REGION;
    }
    unless( $bucket ) {
        $bucket = 'ubos-backup-' . $hostId;
    }
    unless( $name ) {
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime( time() );
        my $now = sprintf( "%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec );

        if( @siteIds == 1 ) {
            $name = sprintf( "site-%s-%s.ubos-backup", $siteIds[0], $now );
        } else {
            $name = sprintf( "multi-%s-%s.ubos-backup", $hostId, $now );
        }
    }

    unless( -r $configFile ) {
        _createConfig( $configFile );
    }

    if( $createBucket ) {
        my $cmd = 's3api create-bucket';
        $cmd .= ' --acl private';
        $cmd .= " --bucket '$bucket'";
        $cmd .= " --region '$region'";
        if( 'us-east-1' ne $region ) {
            $cmd .= " --create-bucket-configuration 'LocationConstraint=$region'"; # strange API
        }

        _aws( $configFile, $cmd );
    }

    my $out = File::Temp->new( DIR => $TMP_DIR );
    
    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();

    my $backup = UBOS::Backup::ZipFileBackup->new();
    my $ret = UBOS::BackupUtils::performBackup( $backup, $out->filename, \@siteIds, \@appConfigIds, $noTls );

    if( $encryptId ) {
        my $gpgFile = $out->filename . '.gpg';
        UBOS::Utils::myexec( "gpg --encrypt -r '$encryptId' " . $out->filename );

        _aws( $configFile, "s3 cp '" . $gpgFile . "' 's3://$bucket/$name.gpg'", $gpgFile );

    } else {
        _aws( $configFile, "s3 cp '" . $out->filename . "' 's3://$bucket/$name'" );
    }
    return $ret;
}

##
# Create the config file
sub _createConfig {
    my $f = shift;

    print "No Amazon credentials found in $f. To set this up, please provide the following information:\n";

    my $content = <<CONTENT;
[$PROFILE_NAME]
region=$DEFAULT_REGION
CONTENT
    foreach my $key ( sort keys %CONFIG_FIELDS ) {
        my $q     = $CONFIG_FIELDS{$key}[0];
        my $regex = $CONFIG_FIELDS{$key}[1];
        my $value = _ask( $q, $regex );

        $content .= "$key=$value\n"
    }

    unless( UBOS::Utils::saveFile( $f, $content, 0600, 'root', 'root' )) {
        fatal( 'Cannot write to config file', $f );
    }

    1;
}

##
# Invoke an aws command
# $configFile: the AWS config file to use
# $cmd: the command
# $deleteThis: name of a file to delete before bailing out
sub _aws {
    my $configFile   = shift;
    my $cmd          = shift;
    my $deleteThis   = shift;

    my $out;
    my $err;
    my $ret = UBOS::Utils::myexec( "AWS_SHARED_CREDENTIALS_FILE='$configFile' aws --profile '$PROFILE_NAME' " . $cmd, undef, \$out, \$err );

    if( $ret ) {
        if( $deleteThis && -e $deleteThis ) {
            unlink( $deleteThis );
        }

        if( $err =~ m!AccessDenied! ) {
            fatal( 'S3 denied access. Check your AWS credentials, and you have permissions to write to the bucket.' );
        } else {
            fatal( $err );
        }
    }
    return $ret;
}

##
# Ask the user a question
# $q: the question text
# $regex: regular expression that defines valid input
# $dontTrim: if false, trim whitespace
sub _ask {
    my $q        = shift;
    my $regex    = shift || '.?';
    my $dontTrim = shift || 0;

    my $ret;
    while( 1 ) {
        print $q . ': ';

        $ret = <STDIN>;

        if( defined( $ret )) { # apparently ^D becomes undef
            unless( $dontTrim ) {
                $ret =~ s!\s+$!!;
                $ret =~ s!^\s+!!;
            }
            if( $ret =~ $regex ) {
                last;
            } else {
                print "(input not valid: regex is $regex)\n";
            }
        }
    }
    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--notls] [--config <configfile>] [--bucket <bucket> [--createbucket [--region <region>]]] [--name <name>] ( --siteid <siteid> | --hostname <hostname> )
SSS
    Back up all data from all apps and accessories installed at a currently
    deployed site with siteid to S3 file <name> according to <configfile>. More than
    one siteid may be specified. Alternatively, specify a hostname instead of a
    siteid.
    <configfile> defaults to $DEFAULT_CONFIG_FILE
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--notls] [--config <configfile>] [--bucket <bucket> [--createbucket [--region <region>]]] [--name <name>] --appconfigid <appconfigid>
SSS
    Back up all data from the currently deployed app and its accessories at
    AppConfiguration appconfigid to S3 file <name> according to <configfile>. More than
    one appconfigid may be specified.
    <configfile> defaults to $DEFAULT_CONFIG_FILE
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--notls] [--config <configfile>] [--bucket <bucket> [--createbucket [--region <region>]]] [--name <name>]
SSS
    Back up all data from all currently deployed apps and accessories at all
    deployed sites to S3 file <name> according to <configfile>.
    <configfile> defaults to $DEFAULT_CONFIG_FILE
HHH
    };
}

1;
