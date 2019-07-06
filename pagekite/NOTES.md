Notes on pagekite
=================

Modes
-----

There are two modes we support:

* ``ubos-admin start-pagekite --all``: UBOS will automatically update
  the pagekite configuration when sites are added or removed, so
  all the sites deployed on the device at any time will always be
  available through pagekite.

* ``ubos-admin start-pagekite`` (not with ``-all``): only the sites
  named as part of this command will be available through pagekite;
  future changes to the set of sites will not impact what pagekite
  forwards. At the minimum, one kite needs to be specified.


As there may or may not be any sites on the device for which we run
kites, we may or may not run the pagekite.service systemd service.

The status file keeps track.

Pagekite frontend vs backend
----------------------------

We have no insight into the Pagekite backend. So we do not know which
kites are enabled / disabled / ... on the backend. When we talk about
kites, it's what's in the config file on the frontend that runs on the
UBOS device.

Implementation
--------------

In the implementation, we distinguish between:
* enabled kites: the kites that were specified on the command-line when
  the user said `ubos-admin start-pagekite`. The special case is
  when `allKites` is true, which means all at the current time.

* active kites: the kites that pagekite is actively serving. This is
  generally the same set as the enabled kites, minus the kites that
  would go with sites not currently deployed
