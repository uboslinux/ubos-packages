#!/usr/bin/perl
#
# A transfer protocol to/from Storj by means of the local Storj
# gateway.
# Compare with the S3 protocol in package amazons3. There is not much
# that could be simplified with a common superclass, so we don't.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::DataTransferProtocols::Storj;

use base qw( UBOS::AbstractDataTransferProtocol );

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Logging;
use UBOS::Terminal;
use UBOS::Utils;
use URI;

my $DEFAULT_ENDPOINT_URL = 'http://127.0.0.1:7777/';
my $AWS_PROFILE_NAME     = 'backup';

##
# Factory method.
# If successful, return instance. If not, return undef.
# $location: the location to parse
# $dataTransferConfig: data transfer configuration options
# $argsP: array of remaining command-line arguments
# return: instance or undef
sub parseLocation {
    my $self               = shift;
    my $location           = shift;
    my $dataTransferConfig = shift;
    my $argsP              = shift;

    my $uri = URI->new( $location );
    if( !$uri->scheme() || $uri->scheme() ne protocol() ) {
        return undef;
    }

    my $accessKeyId = undef;
    my $endpointUrl = $DEFAULT_ENDPOINT_URL;
    # Not secret access key

    my $parseOk = GetOptionsFromArray(
            $argsP,
            'access-key-id=s' => \$accessKeyId,
            'endpoint-url=s'  => \$endpointUrl );
    unless( $parseOk ) {
        return undef;
    }

    if( $accessKeyId && $accessKeyId !~ m!^.+$! ) { # Can we do better?
        fatal( 'Invalid access key id:', $accessKeyId );
    }
    if( $endpointUrl && endpointUrl !~ m!^https?://.+! ) {
        fatal( 'Invalid endpoint URL:', $endpointUrl );
    }

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $location, protocol() );

    if( $accessKeyId ) {
        $dataTransferConfig->removeValue( 'storj', $uri->authority(), 'secret-access-key' ); # ask the user again
    }

    if( $accessKeyId ) {
        $dataTransferConfig->setValue( 'storj', $uri->authority(), 'access-key-id', $accessKeyId );
    }
    if( $endpointUrl ) {
        $dataTransferConfig->setValue( 'storj', $uri->authority(), 'endpoint-url', $endpointUrl );
    }

    unless( $dataTransferConfig->getValue( 'storj', $uri->authority(), 'access-key-id' )) {
        fatal( 'No default access key ID found. Specify with --access-key-id <keyid>' );
    }
    unless( $dataTransferConfig->getValue( 'storj', $uri->authority(), 'secret-access-key' )) {
        my $secretAccessKey = askAnswer( 'Storj secret access key: ', '^[A-Za-z0-9/+]{40}$', undef, 1 );
        $dataTransferConfig->setValue( 'storj', $uri->authority(), 'secret-access-key', $secretAccessKey );
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
# $dataTransferConfig: data transfer configuration options
# return: success or fail
sub send {
    my $self               = shift;
    my $localFile          = shift;
    my $toFile             = shift;
    my $dataTransferConfig = shift;

    my $uri = URI->new( $toFile );

    my $tmpDir = UBOS::Host::tmpdir();

    # Create a temporary AWS config file
    my $awsConfigFile = File::Temp->new( DIR => $tmpDir, UNLINK => 1 );
    chmod 0600, $awsConfigFile;

    my $awsConfig = sprintf( <<CONTENT,
[%s]
region=
aws_access_key_id=%s
aws_secret_access_key=%s
CONTENT
                    $AWS_PROFILE_NAME,
                    $dataTransferConfig->getValue( 'storj', $uri->authority(), 'access-key-id' ),
                    $dataTransferConfig->getValue( 'storj', $uri->authority(), 'secret-access-key' ));

    UBOS::Utils::saveFile(
            $awsConfigFile,
            $awsConfig,
            0600 );

    my $endpointUrl = $dataTransferConfig->getValue( 'storj', $uri->authority(), 'endpoint-url' );

    info( 'Uploading to', $toFile );
    if( _aws( $awsConfigFile, $endpointUrl, "s3 cp '$localFile' '$toFile'" )) {
        # parent emits error message
        return 0;
    }
    return 1;
}

##
# The supported protocol.
# return: the protocol
sub protocol {
    return 'sj';
}

##
# Description of this data transfer protocol, to be shown to the user.
# return: description
sub description {
    return <<TXT;
Transfer to and from Storj/Tardigrade through a locally running Storj gateway.
For security reasons, credentials come from the config file, or must be
entered on the terminal. Options:
--access-key-id <keyid> : Access key id to access the Storj gateway
TXT
}

##
# Invoke an aws command
# $configFile: the AWS config file to use
# $endpointUrl: URL at which the Storj gateway is running
# $cmd: the command
sub _aws {
    my $configFile  = shift;
    my $endpointUrl = shift;
    my $awsCmd      = shift;

    my $out;
    my $ret = UBOS::Utils::myexec(
            "AWS_SHARED_CREDENTIALS_FILE='$configFile'"
                    . " aws --profile '$AWS_PROFILE_NAME'"
                    . " --endpoint-url '$endpointUrl'"
                    . " $awsCmd",
            undef,
            \$out,
            \$out );

    if( $ret ) {
        if( $out =~ m!AccessDenied! ) {
            $@ = 'Storj denied access. Check your credentials, and your permissions to write to the bucket.';
        } else {
            $@ = $out;
        }
    }
    return $ret;
}

1;
