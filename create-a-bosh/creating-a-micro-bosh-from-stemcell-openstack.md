# Create a Micro BOSH on OpenStack from a stemcell

STATUS: Still being written.

WARNING: This tutorial requires an experimental [OpenStack BOSH CPI](https://github.com/frodenas/openstack-bosh-cpi) not supported by VMWare.

This tutorial shows you how to create your first BOSH on OpenStack using a custom stemcell. This is one of several tutorials for [creating a BOSH](creating-a-bosh-overview.md).

In BOSH terminology, you will be creating a Micro BOSH. You will provision a single VM that contains all the parts of BOSH, which is bootstrapped from a custom image (called a "stemcell" in BOSH language). That is, the image contains all the software packages required to run BOSH. During the deployment, a custom OpenStack image will be created, which will be used to boot the Micro BOSH VM.

This tutorial will take you through the steps related to preparation, creating the configuration file, creating a custom stemcell, and using the BOSH CLI to deploy the Micro BOSH VM.

## What will happen in this tutorial

There are three machines/VM being referenced in this tutorial. In addition to your local machine, we will create two VMs:

1. Local machine - use fog to provision Inception VM
1. Inception VM - prepare an available Ubuntu VM; we'll create a new one
1. Micro BOSH VM - use BOSH CLI to bootstrap a new VM that is a BOSH (called "Micro BOSH")

That is, by the end of this tutorial you will have two Ubuntu VMs. An Inception VM used to create a BOSH VM.

[sidebar] 

The Inception VM is used to:

* create a custom micro BOSH stemcell
* create an OpenStack image from the custom micro BOSH stemcell
* run a registry of OpenStack to track provisioned components in OpenStack
* store a registry of deployed Micro BOSHes
* store log files of BOSH CLI interactions with each Micro BOSH

[/sidebar]

## Prerequisites

You'll need an [OpenStack Essex (2012.1)](http://openstack.org/software/essex/) installation.

If you have access to a unused baremetal server, you can build a complete OpenStack environment using these resources:

* [DevStack](http://devstack.org/)
* [hastexo! tutorial](http://www.hastexo.com/resources/docs/installing-openstack-essex-20121-ubuntu-1204-precise-pangolin)

When you install OpenStack, there are 2 important requirements you must fulfill:

* Be sure your flavors include ephemeral disk space
* The network name for your VMs must be "private" and/or "public"

Once you've installed and tested your OpenStack box, you'll need to [upload](http://docs.openstack.org/developer/glance/glance.html#examples-of-uploading-different-kinds-of-images) an [Ubuntu 10.04 LTS 64-bit image](http://uec-images.ubuntu.com/lucid/current/) before proceeding with the next steps.

## Create the Inception VM

We will use fog to create the first Ubuntu VM on OpenStack. You could alternately create one any way that you want. In the next section we will prepare the VM with all the packages and source required for deploying a BOSH VM.

### Setup

In this tutorial we're going to use a command-line program called [fog](http://fog.io) to create our Inception VM.

Three setup steps to run on your local machine:

1. Create SSH keys
1. Install fog
1. Create `.fog` credentials file (with your OpenStack API credentials)

If you've never created SSH keys before, run the following command to create `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub` files:

```
$ ssh-keygen
```

Install latest version of fog as a RubyGem:

```
$ gem install fog --no-ri --no-rdoc
```

Edit your default fog OpenStack credentials:

```
$ vim ~/.fog

:default:
 :openstack_auth_url: OS_AUTH_URL
 :openstack_username: OS_USERNAME
 :openstack_api_key:  OS_PASSWORD
 :openstack_tenant:   OS_TENANT_NAME
```

### Boot Ubuntu instance

From Wesley's [fog blog post](http://www.engineyard.com/blog/2011/spinning-up-cloud-compute-instances/ "Spinning Up Cloud Compute Instances | Engine Yard Blog"), boot the Ubuntu 10.04 LTS 64-bit image:

``` ruby
# NOTE: replace LUCID_IMAGE_NAME with the name of your Ubuntu 10.04 LTS image you uploaded previously
$ fog
  Welcome to fog interactive!
  :default provides OpenStack and VirtualBox
openstack = Fog::Compute.new(:provider => "OpenStack")
public_key = File.open(File.expand_path('~/.ssh/id_rsa.pub'), 'rb') { |f| f.read }
keypair = openstack.key_pairs.create(:name => "my-fog-keypair", :public_key => public_key)
flavor = openstack.flavors.find { |f| f.name == 'm1.medium' }
image = openstack.images.find { |i| i.name == 'LUCID_IMAGE_NAME' }
server = openstack.servers.create(
  :name => "Inception VM",
  :flavor_ref => flavor.id,
  :image_ref => image.id,
  :key_name => keypair.name,
  :username => 'ubuntu'
)
server.wait_for { ready? }
```

Now check the address of your Inception VM:

```
server.addresses
{"private"=>[{"version"=>4, "addr"=>"10.0.0.2"}]}
```

Depending on your OpenStack configuration, the returned address may vary, but it's important it belongs to a private and/or public network.

The security group for the Inception & BOSH VMs will need some TCP ports opened:

``` ruby
group = openstack.security_groups.find { |sg| sg.name == 'default' }
group.create_security_group_rule(25555, 25555) # BOSH Director API
group.create_security_group_rule(6868, 6868) # Message Bus
group.create_security_group_rule(25889, 25889) # OpenStack Registry API
```

## Preparation

We now need to prepare our Ubuntu VM with the source code to be able to run the Micro BOSH deployment command.

These steps come from the [BOSH documentation](https://github.com/cloudfoundry/oss-docs/blob/master/bosh/documentation/documentation.md#bosh-deployer).

```
$ ssh ubuntu@10.0.0.2
sudo su -
export ORIGUSER=ubuntu
curl https://raw.github.com/drnic/bosh-getting-started/master/scripts/prepare_inception_openstack.sh | bash
source /etc/profile
```

After this script prepares the inception VM, it will display the help information for `bosh micro` CLI commands:

```
$ bosh help micro
micro deploy <stemcell>   Deploy a micro BOSH instance to the currently 
                          selected deployment 
                          --update   update existing instance 
micro delete              Delete micro BOSH instance (including 
                          persistent disk) 
micro deployment [<name>] Choose micro deployment to work with 
micro agent <args>        Send agent messages 
micro apply <spec>        Apply spec 
micro status              Display micro BOSH deployment status 
micro deployments         Show the list of deployments 
```

## Deployment configuration

Each Micro BOSH that you create will be described by a single YAML configuration file, commonly named `micro_bosh.yml`. This allows you to easily reference different Micro BOSH deployments, boot them, change them, and delete them.

We will store them all in `/var/vcap/deployments` (created by `prepare_inception_openstack.sh`)

```
cd /var/vcap/deployments
```

**Why have more than one MicroBOSH?** Each BOSH can only manage a single target infrastructure account. That is, if you want to use BOSH for multiple infrastructures (AWS, OpenStack, vSphere, ...), with different billing accounts then you will need a different BOSH for each permutation.

A simple convention for storing different `micro_bosh.yml` within our deployments folder could be to have folders named for the infrastructure-region-account:

```
# NOTE: only an example; you don't have any micro_bosh.yml files yet
$ find . -name micro_bosh.yml
  ./microbosh-aws-us-east-1/micro_bosh.yml
  ./microbosh-aws-us-west-2/micro_bosh.yml
  ./microbosh-openstack-tenant-1/micro_bosh.yml
  ./microbosh-openstack-tenant-2/micro_bosh.yml
```

**Where do I provision/host each Micro BOSH?** As above, each BOSH can manage VMs, persistant disk volumes and network associations in a single infrastructure account. That does not mean that the BOSH must be hosted within that same infrastructure/account.

1. You could host all your BOSH deployments in the same account, with each one referencing external accounts.
1. You could host each BOSH deployment in the account that it will be managing.

For this tutorial, we will do option 2 and host the BOSH deployments within the same account that they will be managing. We will use the same OpenStack credentials used to create the first Ubuntu VM.

Create an OpenStack keypair and store the `.pem` file. Inside the Inception VM:

```
curl https://raw.github.com/drnic/bosh-getting-started/master/scripts/create_keypair > /tmp/create_keypair
chmod 755 /tmp/create_keypair
/tmp/create_keypair openstack OS_USERNAME OS_PASSWORD OS_TENANT_NAME OS_AUTH_URL inception

curl https://raw.github.com/drnic/bosh-getting-started/master/scripts/create_micro_bosh_yml > /tmp/create_micro_bosh_yml
chmod 755 /tmp/create_micro_bosh_yml
/tmp/create_micro_bosh_yml microbosh-openstack openstack OS_USERNAME OS_PASSWORD OS_TENANT_NAME OS_AUTH_URL inception PASSWORD
```

This will create a file `microbosh-openstack/micro_bosh.yml` that looks as below with the ALLCAPS values filled in. `PASSWORD` above (e.g. 'abc123') will be replaced by the salted version.

```
---
name: microbosh-openstack

env:
  bosh:
    password: SALTED_PASSWORD

logging:
  level: DEBUG

network:
  type: dynamic

resources:
  cloud_properties:
    instance_type: m1.small

cloud:
  plugin: openstack
  properties:
    openstack:
      auth_url: OS_AUTH_URL
      username: OS_USERNAME
      api_key: OS_PASSWORD
      tenant: OS_TENANT_NAME
      default_key_name: inception
      default_security_groups: ["default"]
      private_key: /home/vcap/.ssh/inception.pem
    registry:
      endpoint: http://admin:admin@localhost:25889
      user: admin
      password: admin
```

## Custom Stemcell

Remember the warning at the top of this page? Oh yeah, this is an experiment, so we won't find any public OpenStack stemcell. But don't worry, we can create our custom stemcell!!!

NOTE: This is an extremely slow process, so better take a long nap and come later!!!

### Build the BOSH release

First of all create a tarball of the BOSH release (a packaged bundle of software bits and configurations):

```
cd /var/vcap/releases/bosh-release
bosh create release --with-tarball
```

If this is the first time you run `bosh create release` in the release repo, it will ask you to name the release, e.g. "bosh". The output will be at `/var/vcap/releases/bosh-release/dev_releases/bosh-x.y-dev.tgz`.

```
Release version: x.y-dev
Release manifest: /var/vcap/releases/bosh-release/dev_releases/bosh-x.y-dev.yml
Release tarball (95.2M): /var/vcap/releases/bosh-release/dev_releases/bosh-x.y-dev.tgz
```

### Create manifest

Now you need to create the micro BOSH manifest file, call it `openstack_micro.yml`:

```
cd /var/vcap/manifests
curl https://raw.github.com/drnic/bosh-getting-started/master/examples/microbosh-openstack/openstack_micro.yml > openstack_micro.yml
```

### Build the chroot

Create the base contents of the OpenStack stemcell (a vm template with an [embedded BOSH Agent](https://github.com/cloudfoundry/bosh/tree/master/agent)):

```
cd /var/vcap/bootstrap/bosh/agent
rake stemcell:chroot_tgz[openstack]
```

This outputs `Generated chroot tgz: /var/tmp/bosh/agent-x.y.z-nnnnn/chroot-openstack.tgz`.

Optional: If you need to repeat this process several times, you can speed it up if you download an Ubuntu 10.04 LTS 64-bit ISO and put it into `/var/tmp`:

```
cd /var/tmp
wget 'http://releases.ubuntu.com/lucid/ubuntu-10.04.4-server-amd64.iso'
mv ubuntu-10.04.4-server-amd64.iso ubuntu.iso
```

### Build micro BOSH stemcell

Now you have all the pieces to assemble the micro BOSH OpenStack stemcell:

```
cd /var/vcap/bootstrap/bosh/agent
rake stemcell:micro[micro_bosh:openstack,/var/vcap/manifests/openstack_micro.yml,/var/vcap/releases/bosh-release/dev_releases/bosh-x.y-dev.tgz,/var/tmp/bosh/agent-x.y.z-nnnnn/chroot-openstack.tgz]
```

This outputs:

```
Generated stemcell: /var/tmp/bosh/agent-x.y.z-nnnnn/bosh-stemcell-openstack-x.y.z.tgz
Check /var/tmp/bosh/agent-x.y.z-nnnnn for build artifacts
```

### Deploy the micro BOSH image

Normal behaviour is to upload the micro BOSH image in the deploy process, but as OpenStack does not yet support creating images from a volume snapshot, we must upload it manually via Glance.

First of all [install Glance](http://glance.openstack.org/installing.html), and then upload the stemcell image.

Add a kernel (AKI) image to our OpenStack box:

```
$ glance add disk_format=aki container_format=aki name="vmlinuz-2.6.38-15-virtual" < \
  /var/tmp/bosh/agent-x.y.z-nnnnn/chroot/boot/vmlinuz-2.6.38-15-virtual
Uploading image 'vmlinuz-2.6.38-15-virtual'
===============================================================================[100%] 2.77M/s, ETA  0h  0m  0s
Added new image with ID: 5b35a2ab-387e-4816-9dd3-c4376724ac86
```

Now the ramdisk (ARI) image:

```
$ glance add disk_format=ari container_format=ari name="initrd.img-2.6.38-15-virtual" < \
  /var/tmp/bosh/agent-x.y.z-nnnnn/chroot/boot/initrd.img-2.6.38-15-virtual
Uploading image 'initrd.img-2.6.38-15-virtual'
=====================================================================================[100%] 11.8M/s, ETA  0h  0m  0s
Added new image with ID: 48502cfe-ff04-4837-a96a-082091b7ef11
```

List the available images:

```
$ glance index
ID                                   Name                           Disk Format          Container Format     Size
------------------------------------ ------------------------------ -------------------- -------------------- --------------
48502cfe-ff04-4837-a96a-082091b7ef11 initrd.img-2.6.38-15-virtual   ari                  ari                         8704549
5b35a2ab-387e-4816-9dd3-c4376724ac86 vmlinuz-2.6.38-15-virtual      aki                  aki                         4599504
f1baf169-7bb7-4f84-a0f1-4b547e1b42be lucid-server-cloudimg-amd64    ami                  ami                      1476395008
02c62c94-601a-4357-a5fe-c7de9b7911d2 lucid-server-cloudimg-amd64-lo ari                  ari                           91708
2a7a68d9-8fca-479a-ad3d-051b36f1ce77 lucid-server-cloudimg-amd64-vm aki                  aki                         4119680
```

Now we're going to upload the micro BOSH stemcel (AMI) (remember to change the kernel_id and ramdisk_id at the below command with the ID of your images):

```
$ glance add name="microbosh-stemcell-openstack-0.6.1" container_format="ami" disk_format="ami" is_public=true \
  kernel_id="5b35a2ab-387e-4816-9dd3-c4376724ac86" \
  ramdisk_id="48502cfe-ff04-4837-a96a-082091b7ef11" < \
  /var/tmp/bosh/agent-x.y.z-nnnnn/ubuntu-xen/root.img
Uploading image 'microbosh-stemcell-openstack-0.6.1'
====================================================================================[100%] 41.3M/s, ETA  0h  0m  0s
Added new image with ID: 0966813e-79f1-4a95-8ffa-a9bdf573028b
```

Now check that all images are registered in Glance:

```
$ glance index
ID                                   Name                           Disk Format          Container Format     Size
------------------------------------ ------------------------------ -------------------- -------------------- --------------
0966813e-79f1-4a95-8ffa-a9bdf573028b microbosh-stemcell-openstack-0 ami                  ami                      4294967296
48502cfe-ff04-4837-a96a-082091b7ef11 initrd.img-2.6.38-15-virtual   ari                  ari                         8704549
5b35a2ab-387e-4816-9dd3-c4376724ac86 vmlinuz-2.6.38-15-virtual      aki                  aki                         4599504
f1baf169-7bb7-4f84-a0f1-4b547e1b42be lucid-server-cloudimg-amd64    ami                  ami                      1476395008
02c62c94-601a-4357-a5fe-c7de9b7911d2 lucid-server-cloudimg-amd64-lo ari                  ari                           91708
2a7a68d9-8fca-479a-ad3d-051b36f1ce77 lucid-server-cloudimg-amd64-vm aki                  aki                         4119680
```

## Deployment

We now use the BOSH CLI, on the Inception VM, to deploy the Micro BOSH. Tell the BOSH CLI which Micro BOSH deployment "microbosh-openstack" to work on:

```
$ cd /var/vcap/deployments
$ bosh micro deployment microbosh-openstack
WARNING! Your target has been changed to `http://microbosh-openstack:25555'!
Deployment set to '/var/vcap/deployments/microbosh-openstack/micro_bosh.yml'
```

Deploy the deployment using the stemcell image you uploaded previously, replacing `YOUR_IMAGE_UUID` with the OpenStack image UUID:

```
$ bosh micro deploy YOUR_IMAGE_UUID
Deploying new micro BOSH instance `microbosh-openstack/micro_bosh.yml' to `http://microbosh-openstack:25555' (type 'yes' to continue): yes

Deploy Micro BOSH
  using existing stemcell (00:00:00)
  creating VM from 0966813e-79f1-4a95-8ffa-a9bdf573028b (00:00:13)
  waiting for the agent (00:01:32)
  create disk (00:00:02)
  mount disk (00:00:06)
  fetching apply spec (00:00:00)
  stopping agent services (00:00:01)
  applying micro BOSH spec (00:00:10)
  starting agent services (00:00:00)
  waiting for the director (00:00:48)
Done             11/11 00:02:58
WARNING! Your target has been changed to `http://10.0.0.3:25555'!
Deployment set to '/var/vcap/deployments/microbosh-openstack/micro_bosh.yml'
Deployed `microbosh-openstack/micro_bosh.yml' to `http://microbosh-openstack:25555', took 00:02:58 to complete
```

NOTE: To run the `bosh micro deployment microbosh-openstack` command you must be in a folder that itself contains a folder `microbosh-openstack` that contains `micro-bosh.yml`. In our tutorial, we are in `/var/vcap/deployments` which contains `/var/vcap/deployments/microbosh-openstack/micro-bosh.yml`.

We can now connect to our BOSH!

```
$ bosh target http://10.0.0.3
Target set to 'micro (http://10.0.0.3:25555) Ver: 0.6.2 (release:bfc39b70 bosh:59cbcb8f)'
Your username: admin
Enter password: *****
Logged in as 'admin'
```

Username/password was configured as admin/admin unless you changed it.

If you ask your BOSH a few questions it will tell you the following:

```
$ bosh status
Updating director data... done

Target         micro (http://10.0.0.3:25555) Ver: 0.6.2 (release:bfc39b70 bosh:59cbcb8f)
UUID           2137f5c8-56ae-44f1-8d48-d18a42442f1a
User           admin
Deployment     not set
```

Good job!

### Deployment logging

If you want to watch the deployment process in more granular detail, you can tail the log file during deployment.

In another terminal, run:

```
$ ssh ubuntu@10.0.0.2
sudo su -

cd /var/vcap/deployments
tail -f microbosh-openstack/bosh_micro_deploy.log
```

### Checking Status of a micro BOSH deploy

The status command will show the persisted state for a given micro BOSH instance:

```
$ bosh micro status
Stemcell CID   0966813e-79f1-4a95-8ffa-a9bdf573028b
Stemcell name  0966813e-79f1-4a95-8ffa-a9bdf573028b
VM CID         d17494ce-dfe9-4acf-9c08-44d8c230f61d
Disk CID       19
Micro BOSH CID bm-1f9fd181-9a4b-4245-afa9-2810157c09d2
Deployment     /var/vcap/deployments/microbosh-openstack/micro_bosh.yml
Target         micro (http://10.0.0.3:25555) Ver: 0.6.2 (release:bfc39b70 bosh:59cbcb8f)
```

### Listing Deployments

The `deployments` command prints a table view of deployments/bosh-deployments.yml:

```
$ bosh micro deployments

+---------------------+--------------------------------------+--------------------------------------+
| Name                | VM name                              | Stemcell name                        |
+---------------------+--------------------------------------+--------------------------------------+
| microbosh-openstack | d17494ce-dfe9-4acf-9c08-44d8c230f61d | 0966813e-79f1-4a95-8ffa-a9bdf573028b |
+---------------------+--------------------------------------+--------------------------------------+

Deployments total: 1
```

### Sending messages to the micro BOSH agent

The CLI can send messages over HTTP to the agent using the `agent` command:

```
$ bosh micro agent ping
"pong"
$ bosh micro agent noop
"nope"
```

### Administration

WARNING: There is a default admin user created with a default password "admin". Please change this password immediately.

```
$ bosh create user admin
Enter password: *****************

# or

$ bosh create user admin very-long-and-secure-passphrase
```

Then re-login

```
$ bosh login
Your username: admin
Enter password: *****************
Logged in as 'admin'
```

You can now create user accounts the same way.

## Destroy your Micro BOSH

You can delete a specific Micro BOSH deployment:

```
$ cd /var/vcap/deployments
$ bosh micro deployment microbosh-openstack
$ bosh micro delete

You are going to delete micro BOSH deployment `microbosh-openstack'.

THIS IS A VERY DESTRUCTIVE OPERATION AND IT CANNOT BE UNDONE!

Are you sure? (type 'yes' to continue): yes

Delete micro BOSH
  stopping agent services (00:00:01)
  unmount disk (00:00:07)
  detach disk (00:00:11)
  delete disk (00:00:40)
  delete VM (00:00:15)
  preserving stemcell (00:00:00)
Done             6/6 00:01:16
Deleted deployment 'microbosh-openstack', took 00:01:16 to complete
```
