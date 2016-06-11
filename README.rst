=============
Training labs
=============

About
-----

Provide an automated way to deploy Vanilla OpenStack and closely follow
`OpenStack Install Guide <http://docs.openstack.org/#install-guides>`_.

We strove to give easy way to setup OpenStack cluster which should
be a good starting point for beginners to learn OpenStack, and for advanced
users to test out new features, check out different capabilities of OpenStack.
On top of that training-labs will also be a good way to test the install
guides on a regular basis.

Training-labs is a project under OpenStack Documentation. For more information
see the `OpenStack wiki <https://wiki.openstack.org/wiki/Documentation/training-labs>`_.

* Free software: Apache license
* Documentation: http://docs.openstack.org/developer/training-labs
* Source: http://git.openstack.org/cgit/openstack/training-labs
* Bugs: http://bugs.launchpad.net/training-labs

OpenStack Release
-----------------

The current release is master which usually means that we are developing for the next
OpenStack release. The current one is ``OpenStack Newton``. For non-development purposes
(training etc.) please checkout the stable branches. Assuming that ``$remote`` is your
remote branch (usually origin) and ``$release`` is the release version.

    $ git checkout $remote/stable/$release

Pre-requisite
-------------

* Download and install `VirtualBox <https://www.virtualbox.org/wiki/Downloads>`_.

How to run the scripts
----------------------

Clone the training-labs repository:

    $ git clone git://git.openstack.org/openstack/training-labs.git

Change directory:

    $ cd training-labs/labs/osbash/

Run the script by:

    $ ./osbash.sh -g gui -b cluster

What the script installs
------------------------

Running this will automatically spin up 3 virtual machines in VirtualBox/KVM:

* Controller node
* Network node
* Compute node

Now you have a multi-node deployment of OpenStack running with the below services installed.

OpenStack services installed on Controller node:

* Keystone
* Horizon
* Glance
* Nova

  * nova-api
  * nova-scheduler
  * nova-consoleauth
  * nova-cert
  * nova-novncproxy
  * python-novaclient

* Neutron

  * neutron-server

* Cinder

Openstack services installed on Network node:

* Neutron

  * neutron-plugin-openvswitch-agent
  * neutron-l3-agent
  * neutron-dhcp-agent
  * neutron-metadata-agent

Openstack Services installed on Compute node:

* Nova

  * nova-compute

* Neutron

  * neutron-plugin-openvswitch-agent

How to access the services
--------------------------

There are two ways to access the services:

* OpenStack Dashboard (horizon)

You can access the dashboard at: http://192.168.100.51/horizon

Admin Login:

* Username: ``admin``
* Password: ``admin_pass``

Demo User Login:

* Username: ``demo``
* Password: ``demo_pass``

You can ssh to each of the nodes by::

    # Controller node
    $ ssh osbash@10.0.0.11

    # Network node
    $ ssh osbash@10.0.0.21

    # Compute node
    $ ssh osbash@10.0.0.31

Credentials for all nodes:

* Username: ``osbash``
* Password: ``osbash``

After you have ssh access, you need to source the OpenStack credentials in order to access the services.

Two credential files are present on each of the nodes:

* ``demo-openstackrc.sh``
* ``admin-openstackrc.sh``

Source the following credential files

For Admin user privileges::

    $ source admin-openstackrc.sh

For Demo user privileges::

    $ source demo-openstackrc.sh

Now you can access the OpenStack services via CLI.

Specs
-----

To review specifications, see http://specs.openstack.org/openstack/docs-specs/specs/liberty/traininglabs.html

Mailing lists, IRC
------------------

To contribute, join the IRC channel, ``#openstack-doc``, on IRC freenode
or write an e-mail to the OpenStack Documentation Mailing List
``openstack-docs@lists.openstack.org``. Please use ``[training-labs]`` tag in the
subject of the email message.

You might consider
`registering on the OpenStack Documentation Mailing List <http://lists.openstack.org/cgi-bin/mailman/listinfo/openstack-docs>`_
if you want to post your e-mail instantly. It may take some time for
unregistered users, as it requires an administrator's approval.

Sub-team leads
--------------

Feel free to ping Roger or Pranav on the IRC channel ``#openstack-doc`` regarding
any queries about the Labs section.

* Roger Luethi

  * Email: ``rl@patchworkscience.org``
  * IRC: ``rluethi``

* Pranav Salunke

  * Email: ``dguitarbite@gmail.com``
  * IRC: ``dguitarbite``

Meetings
--------

Team meeting for training-labs is on alternating Thursdays on Google Hangouts.
https://wiki.openstack.org/wiki/Documentation/training-labs#Meeting_Information

Wiki
----

Follow various links on training-labs here:
https://wiki.openstack.org/wiki/Documentation/training-labs#Meeting_Information
