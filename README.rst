========================
Team and repository tags
========================

.. image:: https://governance.openstack.org/tc/badges/training-labs.svg
    :target: https://governance.openstack.org/tc/reference/tags/index.html

.. Change things from this point on

=============
Training labs
=============

About
-----

Training-labs provides an automated way to deploy Vanilla OpenStack, closely
following the
`OpenStack Install Guide <https://docs.openstack.org/install-guide>`_.

Training-labs offers an easy way to set up an OpenStack cluster which is a good
starting point for beginners to learn OpenStack, and for advanced users to test
out new features, and check out different capabilities of OpenStack.

On top of that training-labs is also a good way to test the installation
instructions on a regular basis.

Training-labs is a project under OpenStack Documentation. For more information
see the
`OpenStack wiki <https://wiki.openstack.org/wiki/Documentation/training-labs>`_.

* Free software: Apache license
* `Documentation:openstack-training-labs <https://docs.openstack.org/training_labs/>`_
* `Source:openstack/training-labs <https://git.openstack.org/cgit/openstack/training-labs>`_
* `Bugs:openstack-training-labs <https://bugs.launchpad.net/labs>`_
* `Release Notes:openstack-training-labs <https://docs.openstack.org/releasenotes/openstack-manuals/>`_

Pre-requisite
-------------

* Download and install `VirtualBox <https://www.virtualbox.org/wiki/Downloads>`_.

VirtualBox is the default hypervisor used by training-labs. Alternatively, you can use KVM (just set ``PROVIDER=kvm`` in ``labs/config/localrc``).


Getting the Code for an OpenStack Release
-----------------------------------------

The current release is master which usually deploys the current stable
OpenStack release. Unless you have a reason to go with an older release,
we recommend using master.

For non-development purposes (training, etc.), the easiest way to get the code is through downloading the desired archive from
`OpenStack Training Labs <https://docs.openstack.org/training_labs/>`_.
Unpack the archive and you are good to go.

How to run the scripts for GNU/Linux and macOS
----------------------------------------------

Change directory::

    $ cd training-labs/labs/

By default, the cluster is built on Virtualbox VMs.

Run the script by::

    $ ./st.py -b cluster

How to run the scripts for Windows
----------------------------------

The easiest and recommended way to get everything you need besides
VirtualBox is to download a zip file for Windows from the
`Training Labs page <https://docs.openstack.org/training_labs/>`_.

The zip files include pre-generated Windows batch files.

Creates the host-only networks used by the node VMs to communicate::

    > create_hostnet.bat

Creates the base disk::

    > create_base.bat

Creates the node VMs based on the base disk::

    > create_ubuntu_cluster_node.bat

What the script installs
------------------------

Running this will automatically spin up 2 virtual machines in VirtualBox/KVM:

* Controller node
* Compute node

Now you have a multi-node deployment of OpenStack running with the following services installed.

* Keystone
* Nova
* Neutron
* Glance
* Cinder
* Horizon

How to access the services
--------------------------

There are two ways to access the services:

* OpenStack Dashboard (horizon)

You can access the dashboard at: http://10.0.0.11/horizon

Admin Login:

* Username: ``admin``
* Password: ``admin_pass``

Demo User Login:

* Username: ``demo``
* Password: ``demo_pass``

You can ssh to each of the nodes by::

    # Controller node
    $ ssh osbash@10.0.0.11

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

Note: Instead 'source' you can use '.', or you define an alias.
Now you can access the OpenStack services via CLI.

Specs
-----

To review specifications, see `Training-labs
<https://specs.openstack.org/openstack/docs-specs/specs/liberty/training-labs.html>`_

Mailing lists, IRC
------------------

To contribute, join the IRC channel, ``#openstack-doc``, on IRC freenode
or write an e-mail to the OpenStack Development Mailing List
``openstack-discuss@lists.openstack.org``. Please use ``[training-labs]`` tag in the
subject of the email message.

You may have to
`subscribe to the OpenStack Development Mailing List <http://lists.openstack.org/cgi-bin/mailman/listinfo/openstack-discuss>`_
to have your mail accepted by the mailing list software.

Sub-team leads
--------------

Feel free to ping Roger, Julen, or Pranav via email or on the IRC channel
``#openstack-doc`` regarding any queries about training-labs.

* Roger Luethi

  * Email: ``rl@patchworkscience.org``
  * IRC: ``rluethi``

* Pranav Salunke

  * Email: ``dguitarbite@gmail.com``
  * IRC: ``dguitarbite``

* Julen Larrucea

  * Email: ``julen@larrucea.eu``
  * IRC: julen, julenl

Meetings
--------

Training-labs uses the Doc Team Meeting:
https://wiki.openstack.org/wiki/Meetings/DocTeamMeeting

Wiki
----

Follow various links on training-labs here:
https://wiki.openstack.org/wiki/Documentation/training-labs
