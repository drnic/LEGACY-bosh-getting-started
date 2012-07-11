# Create a Micro BOSH from a stemcell

STATUS: Still being written.

WARNING: This tutorial requires a yet-to-be-released micro-bosh stemcell 0.6.1. That is, you can't follow this tutorial yet.

This tutorial shows you how to create your first BOSH on AWS (on any region or any available IaaS). This is one of several tutorials for [creating a BOSH](creating-a-bosh-overview.md).

In BOSH terminology, you will be creating a Micro BOSH. You will provision a single VM that contains all the parts of BOSH, which is bootstrapped from a pre-baked generic image (called a "stemcell" in BOSH language). That is, the image contains all the software packages required to run BOSH. During the deployment, a private AMI will be created from the stemcell, which will be used to boot the Micro BOSH VM.

This tutorial will take you through the steps related to preparation, creating the configuration file and using the BOSH CLI to deploy the Micro BOSH VM.

## What will happen in this tutorial

There are three machines/VM being referenced in this tutorial. In addition to your local machine, we will create two VMs in the same AWS region:

1. Local machine - use fog to provision Inception VM; use ssh to access/prepare Inception VM
1. Inception VM - prepare an available Ubuntu VM; we'll create a new one
1. Micro BOSH VM - use BOSH CLI to bootstrap a new VM that is a BOSH (called "Micro BOSH")

That is, by the end of this tutorial you will have two Ubuntu VMs. An Inception VM used to create a BOSH VM. 

NOTE: Both VMs must be in the same IaaS/region because the Inception VM is used to create the private AMI. If you want to deploy a Micro BOSH into different IaaS/regions from the generic stemcell, you also need to create an Inception VM in that IaaS/region.

[sidebar] 

The Inception VM is used to:

* create a private AMI from a generic micro BOSH stemcell
* run a registry of AWS to track provisioned components in AWS
* store a registry of deployed Micro BOSHes
* store log files of BOSH CLI interactions with each Micro BOSH

[/sidebar]

## Create the Inception VM

We will use fog to create the first Ubuntu VM on AWS. You could alternately create one any way that you want. In the next section we will prepare the VM with all the packages and source required for deploying a BOSH VM.

### Setup

In this tutorial we're going to use a command-line program called [fog](http://fog.io) to create our Inception VM, and then later on for provisioning an elastic IP address for the BOSH VM.

Three setup steps to run on your local machine:

1. Create SSH keys
1. Install fog
1. Create `.fog` credentials file (with your [AWS API credentials](https://portal.aws.amazon.com/gp/aws/securityCredentials))

If you've never created SSH keys before, run the following command to create `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub` files:

```
$ ssh-keygen
```


Install latest version of fog as a RubyGem:

```
gem install fog
```

Example `~/.fog` credentials:

```
:default:
  :aws_access_key_id:     PERSONAL_ACCESS_KEY
  :aws_secret_access_key: PERSONAL_SECRET
```

### Boot Ubuntu instance

From Wesley's [fog blog post](http://www.engineyard.com/blog/2011/spinning-up-cloud-compute-instances/ "Spinning Up Cloud Compute Instances | Engine Yard Blog"), boot a vanilla Ubuntu 64-bit image:

``` ruby
$ fog
  Welcome to fog interactive!
  :default provides AWS and VirtualBox
connection = Fog::Compute.new({ :provider => 'AWS', :region => 'us-east-1' })
server = connection.servers.bootstrap({
  :public_key_path => '~/.ssh/id_rsa.pub',
  :private_key_path => '~/.ssh/id_rsa',
  :flavor_id => 'm1.small', # 64 bit, small large
  :bits => 64,
  :username => 'ubuntu'
})
```

**Not using fog?** Here are a selection of AMIs to use that are [used by the fog](https://github.com/fog/fog/blob/master/lib/fog/aws/models/compute/server.rb#L55-66) example above:

```ruby
when 'ap-northeast-1'
  'ami-5e0fa45f'
when 'ap-southeast-1'
  'ami-f092eca2'
when 'eu-west-1'
  'ami-3d1f2b49'
when 'us-east-1'
  'ami-3202f25b'
when 'us-west-1'
  'ami-f5bfefb0'
when 'us-west-2'
  'ami-e0ec60d0'
```

Check that SSH key credentials are setup. The following should return "ubuntu", or similar, and shouldn't timeout.

```
server.ssh("whoami").first.stdout
"ubuntu"
```

Now create an elastic IP and associate it with the instance.

``` ruby
address = connection.addresses.create
address.server = server
server.reload
server.dns_name
"ec2-10-9-8-7.compute-1.amazonaws.com"
```

This DNS name will be used later to SSH into our Inception VM.

The security group for the Inception & BOSH VMs will need some TCP ports opened:

``` ruby
group = connection.security_groups.get("default")
group.authorize_port_range(25555..25555) # BOSH Director API
group.authorize_port_range(6868..6868) # Message Bus
group.authorize_port_range(25888..25888) # AWS Registry API
```


``` ruby
# Create/attach a volume at /dev/sdi (or somewhere free)
volume = connection.volumes.create(:size => 5, :device => "/dev/sdi", :availability_zone => server.availability_zone)
volume.server = server

# Format and mount the volume
server.ssh([
  'sudo mkfs.ext4 /dev/sdi -F', 
  'sudo mkdir -p /var/vcap/store', 
  'sudo mount /dev/sdi /var/vcap/store'])
```

You can now view the mounted 5G volume at `/var/vcap/store`

```
>> puts server.ssh(['df']).first.stdout
Filesystem           1K-blocks      Used Available Use% Mounted on
/dev/sda1              8256952    740388   7097136  10% /
none                    830428       120    830308   1% /dev
none                    880720         0    880720   0% /dev/shm
none                    880720        48    880672   1% /var/run
none                    880720         0    880720   0% /var/lock
none                    880720         0    880720   0% /lib/init/rw
/dev/sdb             153899044    192068 145889352   1% /mnt
/dev/sdi               5160576    141304   4757128   3% /var/vcap/store
```

## Preparation

We now need to prepare our Ubuntu VM with the source code to be able to run the Micro BOSH deployment command.

These steps come from the [BOSH documentation](https://github.com/cloudfoundry/oss-docs/blob/master/bosh/documentation/documentation.md#bosh-deployer).

```
$ ssh ubuntu@ec2-10-9-8-7.compute-1.amazonaws.com
sudo su -
export ORIGUSER=ubuntu
curl https://raw.github.com/drnic/bosh-getting-started/master/scripts/prepare_inception.sh | bash
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

We will store them all in `/var/vcap/deployments` (created by `prepare_inception.sh`)

```
cd /var/vcap/deployments
```

**Why have more than one MicroBOSH?** Each BOSH can only manage a single target infrastructure account and region. That is, if you want to use BOSH for multiple infrastructures (AWS, Rackspace, local vSphere), with different billing accounts, in different regions (AWS us-east-1, AWS us-west-2) then you will need a different BOSH for each permutation.

A simple convention for storing different `micro_bosh.yml` within our deployments folder could be to have folders named for the infrastructure/region:

```
# NOTE: only an example; you don't have any micro_bosh.yml files yet
$ find . -name micro_bosh.yml
  ./microbosh-aws-us-east-1/micro_bosh.yml
  ./microbosh-aws-us-west-2/micro_bosh.yml
```

**Where do I provision/host each Micro BOSH?** As above, each BOSH can manage VMs, persistant disk volumes and network associations in a single infrastructure region and account. That does not mean that the BOSH must be hosted within that same infrastructure/account. 

1. You could host all your BOSH deployments in the same region/account, with each one referencing external region/accounts.
1. You could host each BOSH deployment in the region/account that it will be managing.

For this tutorial, we will do option 2 and host the BOSH deployments within the same region/account that they will be managing. We will use the same AWS credentials used to create the first Ubuntu VM, but will deploy to a different region (although we could deploy to the same region; remember, each region requires a new BOSH deployment).

On your local machine using fog, provision an elastic public IP in the target infrastructure/region (us-west-2 in this tutorial):

``` ruby
>> connection = Fog::Compute.new({ :provider => 'AWS', :region => 'us-east-1' })
>> address = connection.addresses.create
>> address.public_ip
"1.2.3.4"
```

The "1.2.3.4" value will replace `IPADDRESS` in the `micro_bosh.yml` below.

Back to the Inception VM... 

Create an AWS keypair and store the `.pem` file. Inside the Inception VM:

```
curl https://raw.github.com/drnic/bosh-getting-started/master/scripts/create_keypair > /tmp/create_keypair
chmod 755 /tmp/create_keypair
/tmp/create_keypair aws ACCESS_KEY_ID SECRET_ACCESS_KEY us-east-1 inception

curl https://raw.github.com/drnic/bosh-getting-started/master/scripts/create_micro_bosh_yml > /tmp/create_micro_bosh_yml
chmod 755 /tmp/create_micro_bosh_yml
/tmp/create_micro_bosh_yml microbosh-aws-us-east-1 aws ACCESS_KEY SECRET_KEY us-east-1 inception IP_ADDRESS PASSWORD
```

This will create a file `microbosh-aws-us-east-1/micro_bosh.yml` that looks as below with the ALLCAPS values filled in. `PASSWORD` above (e.g. 'abc123') will be replaced by the salted version.

```
---
name: microbosh-aws-us-east-1

env:
  bosh:
    password: SALTED_PASSWORD

logging:
  level: DEBUG

network:
  type: dynamic
  ip: IPADDRESS

resources:
  cloud_properties:
    instance_type: m1.small
    root_device_name: /dev/sda1
    availability_zone: us-east-1a

cloud:
  plugin: aws
  properties:
    aws:
      access_key_id:     ACCESS_KEY_ID
      secret_access_key: SECRET_ACCESS_KEY
      ec2_endpoint: ec2.us-east-1.amazonaws.com
      default_key_name: inception
      default_security_groups: ["default"]
      ec2_private_key: /home/vcap/.ssh/inception.pem
    stemcell:
      kernel_id: aki-b4aa75dd
      disk: 4096
      root_device_name: /dev/sda1
```

## Deployment

We now use the BOSH CLI, on the Inception VM, to deploy the Micro BOSH.

```
$ cd /var/vcap/deployments
$ bosh micro deployment microbosh-aws-us-east-1
WARNING! Your target has been changed to `http://1.2.3.4:25555'!
Deployment set to '/var/vcap/deployments/microbosh-aws-us-east-1/micro_bosh.yml'
```

NOTE: To run the `bosh micro deployment microbosh-aws-us-east-1` command you must be in a folder that itself contains a folder `microbosh-aws-us-east-1` that contains `micro-bosh.yml`. In our tutorial, we are in `/var/vcap/deployments` which contains `/var/vcap/deployments/microbosh-aws-us-east-1/micro-bosh.yml`.

Unlike [deploying Micro BOSH using a public AMI](creating-a-micro-bosh-from-ami.md#deployment), when deploying with a generic stemcell we must explicitly download the stemcell to the Inception VM and use it. 

During this process the Inception VM will create a private AMI within the AWS region, and use that AMI to boot the BOSH VM. This means that the BOSH VM and the Inception VM must be in the same IaaS/region/account.

```
$ bosh public stemcells
# confirm that micro-bosh-stemcell-aws-0.6.1.tgz is the latest one
$ bosh download public stemcell micro-bosh-stemcell-aws-0.6.1.tgz
$ bosh micro deploy micro-bosh-stemcell-aws-0.6.1.tgz
WARNING! Your target has been changed to `http://55.55.55.55:25555'!
Deployment set to '/var/vcap/deployments/microbosh-aws-us-east-1/micro_bosh.yml'
Deployed `microbosh-aws-us-east-1/micro_bosh.yml' to `http://1.2.3.4:25555', took 00:17:20 to complete
```

NOTE: You want one called "micro-bosh-stemcell..." rather than a base stemcell with "aws" in its name.

## Elastic IP

Note that above, we expect the IP address to be 1.2.3.4, but `bosh micro deploy` set the target to `55.55.55.55`. Why?

Currently, `bosh micro deploy` does not finish the job [[CF-74](https://cloudfoundry.atlassian.net/browse/CF-74)] with your elastic IP `1.2.3.4`.

We will manually assign the elastic IP to the Micro BOSH VM.

``` ruby
$ fog
connection = Fog::Compute.new({ :provider => 'AWS', :region => 'us-east-1' })
address = connection.addresses.get('1.2.3.4') # load our elastic IP
server = connection.servers.all('ip-address' => '55.55.55.55').first
address.server = server
```


## Deployment logging

If you want to watch the deployment process in more granular detail, you can tail the log file during deployment.

In another terminal, run:

```
$ ssh ubuntu@ec2-10-9-8-7.compute-1.amazonaws.com
sudo su -

cd /var/vcap/deployments
tail -f microbosh-aws-us-east-1/bosh_micro_deploy.log
```

## Destroy your Micro BOSH

You can delete a specific Micro BOSH deployment:

```
$ cd /var/vcap/deployments
$ bosh micro deployment microbosh-aws-us-east-1
$ bosh micro delete
```

TODO - will the Micro BOSH delete all its own deployments first?
