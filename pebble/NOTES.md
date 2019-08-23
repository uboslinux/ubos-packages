# Howto

To set up a test ACME (aka Letsencrypt) server:
* build and install this package
* create the configuration file in `/etc/pebble/config.json`
* create a certificate authority
* run `pebble`
* point `certbot` to `pebble`

To test UBOS against this, run UBOS in a container on the same
host as where you run pebble. This allows is to use systemd's
built-in DNS server and setup is simpler.

## Create the config file

As root, save file `/etc/pebble/config.json`:

```
{
  "pebble": {
    "listenAddress": "0.0.0.0:14000",
    "certificate": "/etc/pebble/ca.crt",
    "privateKey": "/etc/pebble/ca.key",
    "httpPort": 80,
    "tlsPort": 443,
    "ocspResponderURL": ""
  }
}
```

## Create a certificate authority

As root:

```
openssl genrsa -out /etc/pebble/ca.key 2048
openssl req -x509 -new -nodes -key /etc/pebble/ca.key -sha256 -days 10240 -out /etc/pebble/ca.crt
```
You can accept the default for all of these fields.

## Run `pebble`

As root:

```
pebble
```

## Point `certbot` to `pebble`

Invoke `certbot` with argument:

```
--server https://0.0.0.0:14000/dir --no-verify-ssl
```

e.g. by setting "certbotflags" in `/etc/ubos/config.json` to the above value.

Note that the hostname must exist, so perhaps add to `/etc/hosts` before invoking certbot.
