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

my $DEFAULT_CONFIG_FILE = '/etc/amazons3/backup-config.json';
my $TMP_DIR             = '/var/tmp';
my $AWS_DEFAULT_REGION  = 'us-east-1';
my $AWS_PROFILE_NAME    = 'backup';

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
    my $configFile    = undef;
    my @siteIds       = ();
    my @hostnames     = ();
    my @appConfigIds  = ();
    my $region        = undef;
    my $bucket        = undef;
    my $name          = undef;
    my $noTls         = undef;
    my $noTorKey      = undef;
    my $noStore       = undef;
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

    my $firstTime    = 1;
    my $config       = {}; # by default we have nothing
    my $configChange = 0;
    if( $configFile ) {
        if( -e $configFile ) {
            $config = UBOS::Utils::readJsonFromFile( $configFile );
            unless( $config ) {
                fatal( 'Failed to parse config file:', $configFile );
            }
            $firstTime = 0;
        } else {
            fatal( 'Specified config file does not exist:', $configFile );
        }
    } elsif( -e $DEFAULT_CONFIG_FILE ) {
        $config = UBOS::Utils::readJsonFromFile( $DEFAULT_CONFIG_FILE );
        unless( $config ) {
            fatal( 'Failed to parse config file:', $DEFAULT_CONFIG_FILE );
        }
        $firstTime  = 0;
        $configFile = $DEFAULT_CONFIG_FILE;
    } # else: we don't have a configuration yet.

    # overwrite values if given
    $configChange |= _overrideValue( $config, 'aws-region',    $region );
    $configChange |= _overrideValue( $config, 'aws-bucket',    $bucket );
    $configChange |= _overrideValue( $config, 'aws-region',    $region );
    $configChange |= _overrideValue( $config, 'gpg-encryptid', $encryptId );

    # Don't need to do any cleanup of siteIds or appConfigIds, BackupUtils::performBackup
    # does that for us
    foreach my $hostname ( @hostnames ) {
        my $site = UBOS::Host::findSiteByHostname( $hostname );
        unless( $site ) {
            fatal( 'Cannot find site with hostname:', $hostname );
        }
        push @siteIds, $site->siteId;
    }

    # Ask for values we don't have yet and we need for testing that a
    # bucket exists
    unless( exists( $config->{'aws-access-key-id'} )) {
        $config->{'aws-access-key-id'} = _ask( 'Amazon AWS access key id', '^[A-Z0-9]{20}$', 0 );
        $configChange = 1;
    }
    unless( exists( $config->{'aws-secret-access-key'} )) {
        $config->{'aws-secret-access-key'} = _ask( 'Amazon AWS secret access key', '^[A-Za-z0-9/+]{40}$', 1 );
        $configChange = 1;
    }
    unless( exists( $config->{'aws-bucket'} )) {
        $config->{'aws-bucket'} = _ask( 'Amazon S3 bucket for backup', '^[-.a-z0-9]+$', 0 );
        $configChange = 1;
    }
    unless( exists( $config->{'aws-region'} )) {
        $config->{'aws-region'} = $AWS_DEFAULT_REGION;
        $configChange = 1;
    }

    # Create a temporary AWS config file
    my $awsConfigFile = File::Temp->new( DIR => $TMP_DIR, UNLINK => 1 );
    chmod 0600, $awsConfigFile;

    UBOS::Utils::saveFile(
            $awsConfigFile,
            sprintf(
                    <<CONTENT,
[%s]
region=%s
aws_access_key_id=%s
aws_secret_access_key=%s
CONTENT
                    $AWS_PROFILE_NAME,
                    $config->{'aws-region'},
                    $config->{'aws-access-key-id'},
                    $config->{'aws-secret-access-key'} ),
            0600 );

    # Check whether bucket exists, and if not, create it

    my $awsCmd = 's3api head-bucket';
    $awsCmd .= " --bucket '" . $config->{'aws-bucket'} . "'";
    $awsCmd .= " --region '" . $config->{'aws-region'} . "'";

    if( _aws( $awsConfigFile, $awsCmd ) != 0 ) {
        info( 'Creating S3 bucket', $config->{'aws-bucket'} );
        $awsCmd  = 's3api create-bucket';
        $awsCmd .= ' --acl private';
        $awsCmd .= " --bucket '" . $config->{'aws-bucket'} . "'";
        $awsCmd .= " --region '" . $config->{'aws-region'} . "'";
        if( 'us-east-1' ne $config->{'aws-region'} ) {
            $awsCmd .= " --create-bucket-configuration 'LocationConstraint=" . $config->{'aws-region'} . "'";
            # strange API
        }
        if( _aws( $awsConfigFile, $awsCmd ) != 0 ) {
            fatal( 'S3 Bucket does not exist, and cannot create:', $config->{'aws-bucket'} );
        }
    }

    my $out = File::Temp->new( DIR => $TMP_DIR );

    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();

    my $backup = UBOS::Backup::ZipFileBackup->new();
    my $ret = UBOS::BackupUtils::performBackup( $backup, $out->filename, \@siteIds, \@appConfigIds, $noTls, $noTorKey );
    unless( $ret ) {
        error( $@ );
        return $ret;
    }

    unless( $name ) {
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime( time() );
        my $now = sprintf( "%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec );

        my $actualSites      = $backup->sites();
        my $actualAppConfigs = $backup->appConfigs();

        if( @$actualSites == 1 ) {
            $name = sprintf( "site-%s-%s.ubos-backup", $actualSites->[0]->siteId(), $now );

        } elsif( @$actualSites ) {
            my $hostId = lc( UBOS::Host::gpgHostKeyFingerprint());
            $name = sprintf( "site-multi-%s-%s.ubos-backup", $hostId, $now );

        } elsif( @$actualAppConfigs == 1 ) {
            $name = sprintf( "appconfig-%s-%s.ubos-backup", $actualAppConfigs->[0]->appConfigId(), $now );

        } else {
            my $hostId = lc( UBOS::Host::gpgHostKeyFingerprint());
            $name = sprintf( "appconfig-multi-%s-%s.ubos-backup", $hostId, $now );
        }
    }


    if( exists( $config->{'gpg-encryptid'} ) && $config->{'gpg-encryptid'} ) {
        info( 'Encrypting backup' );

        my $gpgFile = $out->filename . '.gpg';
        UBOS::Utils::myexec( "gpg --encrypt -r '" . $config->{'gpg-encryptid'} . "' " . $out->filename );

        info( 'Uploading' );

        if( _aws( $awsConfigFile, "s3 cp '$gpgFile' 's3://" . $config->{'aws-bucket'} . "/$name.gpg'", $gpgFile )) {
            fatal( "Failed to copy encrypted backup file to S3" );
        }
        info( 'Backed up to', "s3://" . $config->{'aws-bucket'} . "/$name.gpg" );

    } else {
        info( 'Uploading' );

        if( _aws( $awsConfigFile, "s3 cp '" . $out->filename . "' 's3://" . $config->{'aws-bucket'} . "/$name'" )) {
            fatal( "Failed to copy backup file to S3" );
        }
        info( 'Backed up to', "s3://" .  $config->{'aws-bucket'} . "/$name" );
    }

    if( $configChange ) {
        unless( $firstTime ) {
            info( 'Configuration changed. Defaults were updated.' );
        }

        UBOS::Utils::writeJsonToFile(
                defined( $configFile ) ? $configFile : $DEFAULT_CONFIG_FILE,
                $config,
                0600 );
    }
    return $ret;
}

##
# Override a value in the config hash and report whether a change occurred.
sub _overrideValue {
    my $config    = shift;
    my $configKey = shift;
    my $value     = shift;

    unless( $value ) {
        return 0;
    }
    if( exists( $config->{$configKey} ) && $config->{$configKey} eq $value ) {
        return 0; # nothing to do here
    }
    $config->{$configKey} = $value;
    return 1;
}

##
# Invoke an aws command
# $configFile: the AWS config file to use
# $cmd: the command
sub _aws {
    my $configFile = shift;
    my $awsCmd     = shift;

    my $out;
    my $err;
    my $ret = UBOS::Utils::myexec(
            "AWS_SHARED_CREDENTIALS_FILE='$configFile'"
                    . " aws --profile '$AWS_PROFILE_NAME' "
                    . $awsCmd,
            undef,
            \$out,
            \$err );

    if( $ret ) {
        if( $err =~ m!AccessDenied! ) {
            error( 'S3 denied access. Check your AWS credentials, and your permissions to write to the bucket.' );
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
            $ret =~ s!^\s+!!;
            $ret =~ s!\s+$!!;
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
    $DEFAULT_CONFIG_FILE.
HHH
        }
    };
}

1;
