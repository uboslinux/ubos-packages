#!/usr/bin/perl
#
# Command that backs up data on this device to Amazon S3.
#
# This file is part of amazons3
# (C) 2012-2017 Indie Computing Corp.
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

# The awsConfigFile is the file passed into the aws command-line tools
# for credentials. The ubosConfigFile is used to store additional information
# (default bucket, encryption id). ubosConfigFile is a sibling with an extra
# extension.

my $DEFAULT_AWS_CONFIG_FILE = '/etc/amazons3/aws-config-for-backup';
my $UBOS_CONFIG_FILE_EXT    = '.ubos';
my $TMP_DIR                 = '/var/tmp';
my %AWS_CONFIG_FIELDS       = (
    'aws_access_key_id'     => [ 'Amazon AWS access key id',       '^[A-Z0-9]{20}$',            0 ],
    'aws_secret_access_key' => [ 'Amazon AWS secret access key',   '^[A-Za-z0-9/+]{40}$',       1 ]
);
my $DEFAULT_REGION = 'us-east-1';
my $PROFILE_NAME   = 'backup';

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
    my $awsConfigFile = undef;
    my @siteIds       = ();
    my @hostnames     = ();
    my @appConfigIds  = ();
    my $region        = undef;
    my $bucket        = undef;
    my $createBucket  = undef;
    my $name          = undef;
    my $noTls         = undef;
    my $noTorKey      = undef;
    my $encryptId     = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'config=s',     => \$awsConfigFile,
            'siteid=s'      => \@siteIds,
            'hostname=s'    => \@hostnames,
            'appconfigid=s' => \@appConfigIds,
            'region=s'      => \$region,
            'bucket=s'      => \$bucket,
            'createbucket'  => \$createBucket,
            'name=s'        => \$name,
            'notls'         => \$noTls,
            'notorkey'      => \$noTorKey,
            'encryptid=s'   => \$encryptId );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || @args
        || ( $verbose && $logConfigFile )
        || ( @appConfigIds && ( @siteIds + @hostnames )))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( $awsConfigFile ) {
        unless( -r $awsConfigFile ) {
            fatal( 'Config file does not exist or cannot be read:', $awsConfigFile );
        }
    } else {
        $awsConfigFile = $DEFAULT_AWS_CONFIG_FILE;
    }

    my $ubosConfigFile = $awsConfigFile . $UBOS_CONFIG_FILE_EXT;
    my $ubosConfig     = _readUbosConfigIfExists( $ubosConfigFile );
    my $orgUbosConfig  = {};
    map { $orgUbosConfig->{$_} = $ubosConfig->{$_} } keys %$ubosConfig; # keep copy

    # overwrite values if given
    if( $bucket ) {
        $ubosConfig->{'bucket'} = $bucket;
    }
    if( $encryptId ) {
        $ubosConfig->{'encryptId'} = $encryptId;
    }

    # Don't need to do any cleanup of siteIds or appConfigIds, BackupUtils::performBackup
    # does that for us
    foreach my $hostname ( @hostnames ) {
        my $site = UBOS::Host::findSiteByHostname( $hostname );
        unless( $site ) {
            fatal( 'Cannot find site with hostname:', $hostname );
        }
        push @siteIds, $site->siteId;
    }

    my $hostId = lc( UBOS::Host::gpgHostKeyFingerprint());

    if( !exists( $ubosConfig->{'bucket'} ) || ! $ubosConfig->{'bucket'} ) {
        fatal( 'Must specify the S3 bucket to back up to' );
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

    unless( -r $awsConfigFile ) {
        _createAwsConfig( $awsConfigFile );
    }
    if( $createBucket ) {
        unless( $region ) {
            $region = $DEFAULT_REGION;
        }
        # first try to create a bucket before saving bucket info
        my $cmd = 's3api create-bucket';
        $cmd .= ' --acl private';
        $cmd .= " --bucket '$bucket'";
        $cmd .= " --region '$region'";
        if( 'us-east-1' ne $region ) {
            $cmd .= " --create-bucket-configuration 'LocationConstraint=$region'"; # strange API
        }

        _aws( $awsConfigFile, $cmd );
    }

    my $out = File::Temp->new( DIR => $TMP_DIR );

    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();

    my $backup = UBOS::Backup::ZipFileBackup->new();
    my $ret = UBOS::BackupUtils::performBackup( $backup, $out->filename, \@siteIds, \@appConfigIds, $noTls, $noTorKey );

    if( exists( $ubosConfig->{'encryptId'} ) && $ubosConfig->{'encryptId'} ) {
        my $gpgFile = $out->filename . '.gpg';
        UBOS::Utils::myexec( "gpg --encrypt -r '$encryptId' " . $out->filename );

        _aws( $awsConfigFile, "s3 cp '$gpgFile' 's3://" . $ubosConfig->{'bucket'} . "/$name.gpg'", $gpgFile );

        info( 'Backed up to', "s3://" . $ubosConfig->{'bucket'} . "/$name.gpg" );

    } else {
        _aws( $awsConfigFile, "s3 cp '" . $out->filename . "' 's3://" . $ubosConfig->{'bucket'} . "/$name'" );

        info( 'Backed up to', "s3://" .  $ubosConfig->{'bucket'} . "/$name" );
    }

    _saveUbosConfigIfChanged( $ubosConfigFile, $ubosConfig, $orgUbosConfig );

    return $ret;
}

##
# Create the AWS config file
sub _createAwsConfig {
    my $f = shift;

    print "No Amazon credentials found in $f. To set this up, please provide the following information:\n";

    my $content = <<CONTENT;
[$PROFILE_NAME]
region=$DEFAULT_REGION
CONTENT
    foreach my $key ( sort keys %AWS_CONFIG_FIELDS ) {
        my $q     = $AWS_CONFIG_FIELDS{$key}[0];
        my $regex = $AWS_CONFIG_FIELDS{$key}[1];
        my $blank = $AWS_CONFIG_FIELDS{$key}[2];
        my $value = _ask( $q, $regex, $blank );

        $content .= "$key=$value\n"
    }

    unless( UBOS::Utils::saveFile( $f, $content, 0600, 'root', 'root' )) {
        fatal( 'Cannot write to config file', $f );
    }

    1;
}

##
# Save or update the UBOS config.
sub _saveUbosConfigIfChanged {
    my $f         = shift;
    my $values    = shift;
    my $orgValues = shift;

    my $changed = 0;
    if( scalar( %$values ) != scalar( %$orgValues )) {
        $changed = 1;
    } else {
        foreach my $key ( keys %$values ) {
            if( !exists( $orgValues->{$key} )) {
                $changed = 1;
                last;
            }
            if( $values->{$key} ne $orgValues->{$key} ) {
                $changed = 1;
                last;
            }
        }
    }

    if( $changed ) {
        my $content = '';
        foreach my $key ( sort keys %$values ) {
            my $value = $values->{$key};

            $content .= "$key=$value\n"
        }

        unless( UBOS::Utils::saveFile( $f, $content, 0600, 'root', 'root' )) {
            fatal( 'Cannot write to config file', $f );
        }
    }

    return 1;
}

##
# If it exists, read the UBOS config file.
sub _readUbosConfigIfExists {
    my $f = shift;

    my $ret = {};
    if( -r $f ) {
        my $content = UBOS::Utils::slurpFile( $f );
        my @lines   = split( /\n/, $content );

        foreach my $line ( @lines ) {
            $line =~ s!#.*$!!;
            $line =~ s!^\s+!!;
            $line =~ s!\s+$!!;
            if( $line ) {
                my( $key, $value ) = split( '=', $line, 2 );
                $ret->{$key} = $value;
            }
        }
    }

    return $ret;
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
    my $ret = 0;

    # $ret = UBOS::Utils::myexec( "AWS_SHARED_CREDENTIALS_FILE='$configFile' aws --profile '$PROFILE_NAME' " . $cmd, undef, \$out, \$err );
    print( "Should execute: AWS_SHARED_CREDENTIALS_FILE='$configFile' aws --profile '$PROFILE_NAME' " . $cmd . "\n" );

    if( $ret ) {
        if( $deleteThis && -e $deleteThis ) {
            unlink( $deleteThis );
        }

        if( $err =~ m!AccessDenied! ) {
            fatal( 'S3 denied access. Check your AWS credentials, and your permissions to write to the bucket.' );
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
# $blank: if true, do not echo input to the terminal
sub _ask {
    my $q     = shift;
    my $regex = shift || '.?';
    my $blank = shift || 0;

    my $ret;
    while( 1 ) {
        print $q . ': ';

        if( $blank ) {
            system('stty','-echo');
        }
        $ret = <STDIN>;
        if( $blank ) {
            system('stty','echo');
            print "\n";
        }

        if( defined( $ret )) { # apparently ^D becomes undef
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
        'summary' => <<SSS,
    Create a backup and upload it to Amazon S3.
SSS
        'detail' => <<DDD,
    The backup may include all or just some of the sites currently
    deployed on this device. The backup can optionally be encrypted
    prior to uploading. S3 bucket name, AWS credentials and the like are
    stored in a config file on the first run. Its content will be reused
    on subsequent runs unless overridden.
DDD
        'cmds' => {
            '' => <<HHH,
    Back up all data from all sites currently deployed on this device by
    saving all data from all apps and accessories on the device to a
    new file in Amazon S3.
HHH
            <<SSS => <<HHH,
    --siteid <siteid> [--siteid <siteid>]...
SSS
    Back up one or more sites identified by their site ids <siteid> by
    saving all data from all apps and accessories at those sites to a
    new file in Amazon S3.
HHH
            <<SSS => <<HHH,
    --hostname <hostname> [--hostname <hostname>]...
SSS
    Back up one or more sites identified by their hostnames <hostname>
    by saving all data from all apps and accessories at those sites to a
    new file in Amazon S3.
HHH
            <<SSS => <<HHH
    --appconfigid <appconfigid> [--appconfigid <appconfigid>]...
SSS
    Back up one or more AppConfigurations identified by their
    AppConfigIds <appconfigid> by saving all data from the apps and
    accessories for these apps to a new file in Amazon S3.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--notls' => <<HHH,
    If a site uses TLS, do not put the TLS key and certificate into the
    backup.
HHH
            '--notorkey' => <<HHH,
    If a site is on the Tor network, do not put the Tor key into the
    backup.
HHH
            '--nostore' => <<HHH,
    Do not store AWS credentials or other configuration for future
    reuse. If this is given, do not specify --config <configfile>.
HHH
            '--name <name>' => <<HHH,
    Use this file name in S3. If not provided, UBOS will automatically
    generate a file name based on the current time and what is being
    backed up.
HHH
            '--bucket <bucket>' => <<HHH,
    Store the backup in S3 bucket <bucket>. Automatically attempt to
    create the bucket if it does not exist yet.
HHH
            '--encryptid <id>' => <<HHH,
    If given, the backup file will be gpg-encrypted before upload,
    using GPG key id <id> in the current user's GPG keychain.
HHH
            '--config <configfile>' => <<HHH
    Use an alternate configuration file. If this is given, do not
    specify --nostore. Default location of the configuration file is at
    $DEFAULT_AWS_CONFIG_FILE.
HHH
        }
    };
}

1;
