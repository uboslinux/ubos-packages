#!/usr/bin/perl
#
# A transfer protocol to/from Amazon S3.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::DataTransferProtocols::S3;

use base qw( UBOS::AbstractDataTransferProtocol );

use UBOS::Logging;
use UBOS::Terminal;
use UBOS::Utils;
use URI;

my $AWS_DEFAULT_REGION = 'us-east-1';
my $AWS_PROFILE_NAME   = 'backup';

##
# Factory method.
# If successful, return instance. If not, return undef.
# $location: the location to parse
# $argsP: array of remaining command-line arguments
# $config: configuration options
# $configChangedP: set to 1 if this method changed at least one configuration option
# return: instance or undef
sub parseLocation {
    my $self           = shift;
    my $location       = shift;
    my $argsP          = shift;
    my $config         = shift;
    my $configChangedP = shift;

    my $uri = URI->new( $location );
    if( !$uri->scheme() || $uri->scheme() ne protocol() ) {
        return undef;
    }

    my $awsAccessKeyId = undef;
    my $awsBucket      = undef;
    my $awsRegion      = $AWS_DEFAULT_REGION;
    # Not secret access key

    my $parseOk = GetOptionsFromArray(
            $argsP,
            'aws-access-key-id' => \$awsAccessKeyId,
            'aws-bucket'        => \$awsBucket,
            'aws-region'        => \$awsRegion );
    unless( $parseOk ) {
        return undef;
    }

    unless( $awsBucket =~ m!^[-.a-z0-9]+$! ) {
        fatal( 'Invalid AWS bucket:', $awsBucket );
    }
    unless( $awsAccessKeyId =~ m!^[A-Z0-9]{20}$! ) {
        fatal( 'Invalid AWS access key id:', $awsAccessKeyId );
    }

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $location, protocol() );

    $$configChangedP ||= UBOS::AbstractDataTransferProtocol::overrideConfigValue( $config, 's3', 'region', $awsRegion );
    $$configChangedP ||= UBOS::AbstractDataTransferProtocol::overrideConfigValue( $config, 's3', 'bucket', $awsBucket );
    $$configChangedP ||= UBOS::AbstractDataTransferProtocol::overrideConfigValue( $config, 's3', 'access-key-id', $awsAccessKeyId );

    unless( exists( $config->{s3}->{'secret-access-key'} )) {
        my $secretAccessKey = askAnswer( 'AWS secret access key: ', '^[A-Za-z0-9/+]{40}$', undef, 1 );
        $config->{s3}->{'secret-access-key'} = $secretAccessKey;
        $$configChangedP = 1;
    }

    return $self;
}

##
# Is this a local destination?
# return: true or false
sub isLocal {
    my $self = shift;

    return 0;
}

##
# Is this a valid destination?
# $toFile: the candidate destination
# return: true or false
sub isValidToFile {
    my $self   = shift;
    my $toFile = shift;

    return 1;
}

##
# Send a local file to location via this protocol.
# $localFile: the local file
# $toFile: the ultimate destination as a file URL
# $config: configuration options
# return: success or fail
sub send {
    my $self      = shift;
    my $localFile = shift;
    my $toFile    = shift;
    my $config    = shift;

    my $tmpDir = UBOS::Host::tmpdir();

    # Create a temporary AWS config file
    my $awsConfigFile = File::Temp->new( DIR => $tmpDir, UNLINK => 1 );
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
                    $config->{s3}->{region},
                    $config->{s3}->{'access-key-id'},
                    $config->{s3}->{'secret-access-key'} ),
            0600 );

    # Check whether bucket exists, and if not, create it

    my $awsCmd = 's3api head-bucket';
    $awsCmd .= " --bucket '" . $config->{s3}->{bucket} . "'";
    $awsCmd .= " --region '" . $config->{s3}->{region} . "'";

    if( _aws( $awsConfigFile, $awsCmd ) != 0 ) {
        info( 'Creating S3 bucket', $config->{s3}->{bucket} );
        $awsCmd  = 's3api create-bucket';
        $awsCmd .= ' --acl private';
        $awsCmd .= " --bucket '" . $config->{s3}->{bucket} . "'";
        $awsCmd .= " --region '" . $config->{s3}->{region} . "'";
        if( 'us-east-1' ne $config->{s3}->{region} ) {
            $awsCmd .= " --create-bucket-configuration 'LocationConstraint=" . $config->{s3}->{region} . "'";
            # strange API
        }
        if( _aws( $awsConfigFile, $awsCmd ) != 0 ) {
            fatal( 'S3 Bucket does not exist, and cannot create:', $config->{s3}->{bucket} );
        }
    }

    info( 'Uploading to', $toFile );
    if( _aws( $awsConfigFile, "s3 cp '" . $localFile . "' '" . $self->{location} . "'" )) {
        error( "Failed to copy file to S3" );
        return 0;
    }
    return 1;
}

##
# The supported protocol.
# return: the protocol
sub protocol {
    return 's3';
}

##
# Description of this data transfer protocol, to be shown to the user.
# return: description
sub description {
    return <<TXT;
Transfer to and from Amazon S3. For security reasons, credentials come from
the config file, or must be entered on the terminal. Options:
--aws-access-key-id <keyid> : AWS access key id to access S3
--aws-bucket <bucket>       : Name of the S3 bucket
--aws-region <region>       : Name of the S3 region
TXT
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

1;
