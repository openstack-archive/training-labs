=============
training labs
=============

About
-----

Provide an automated way to deploy Vanilla OpenStack and closely follow
.. _install-guides: https://wiki.openstack.org/wiki/Documentation/InstallGuide

We strove to give easy way to setup OpenStack cluster which should
be a good starting point for beginners to learn OpenStack, and for advanced
users to test out new features, check out different capabilities of OpenStack.
On top of that training-labs will also be a good way to test the install
guides on a regular basis.

Training-labs is a project under OpenStack Documentation. Please checkout
the wiki for more information: .. _training-labs: https://wiki.openstack.org/wiki/Documentation/training-labs

* Free software: Apache license
* Documentation: http://docs.openstack.org/developer/training-labs
* Source: http://git.openstack.org/cgit/openstack/training-labs
* Bugs: http://bugs.launchpad.net/training-labs

Pre-requisite
-------------

* Download and install [VirtualBox](https://www.virtualbox.org/wiki/Downloads).

How to run the scripts
----------------------

.. TODO(psalunke: fix me)
1. Clone the training-labs repository:

        $

This will take some time to run the first time.

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

*Username:* `admin`

*Password:* `admin_pass`

*Demo User Login:*

*Username:* `demo`

*Password:* `demo_pass`

* SSH

You can ssh to each of the nodes by:

        # Controller node
        $ ssh osbash@10.10.10.51

        # Network node
        $ ssh osbash@10.10.10.52

        # Compute node
        $ ssh osbash@10.10.10.53

Credentials for all nodes:

*Username:* `osbash`

*Password:* `osbash`

After you have ssh access, you need to source the OpenStack credentials in order to access the services.

Two credential files are present on each of the nodes:
        demo-openstackrc.sh
        admin-openstackrc.sh

Source the following credential files

For Admin user privileges:

        $ source admin-openstackrc.sh

For Demo user privileges:

        $ source demo-openstackrc.sh

Now you can access the OpenStack services via CLI.

Specs
-----

* .. _training-labs: http://specs.openstack.org/openstack/docs-specs/specs/liberty/traininglabs.html

Mailing Lists, IRC
------------------

* To contribute please hop on to IRC on the channel `#openstack-doc` on IRC freenode
  or write an e-mail to the OpenStack Manuals mailing list
  `openstack-docs@lists.openstack.org`. Please use [training-labs] tag in the email
  message.

**NOTE:** You might consider registering on the OpenStack Manuals mailing list if
          you want to post your e-mail instantly. It may take some time for
          unregistered users, as it requires admin's approval.

Sub-team leads
--------------

Feel free to ping Roger or Pranav on the IRC channel `#openstack-doc` regarding
any queries about the Labs section.

* Roger Luethi
** Email: `rl@patchworkscience.org`
** IRC: `rluethi`

* Pranav Salunke
** Email: `dguitarbite@gmail.com`
** IRC: `dguitarbite`

Meetings
--------

Team meeting for training-labs is on alternating Thursdays on Google Hangouts.
https://wiki.openstack.org/wiki/Documentation/training-labs#Meeting_Information

Wiki
----

Follow various links on training-labs here:
https://wiki.openstack.org/wiki/Documentation/training-labs#Meeting_Information
