# Create a BOSH from Scratch

These instructions are a combination of "Boot an AWS instance" and "Install BOSH via its chef_deployer"

Follow along with [this 16 min screencast](https://vimeo.com/40484383).

* Create a VM
* Run prepare_instance.sh inside instance
* Use chef_deployer to setup the VM as BOSH

## Setup

Install fog, `~/.fog` credentials (for AWS), and `~/.ssh/id_rsa(.pub)` keys

Install fog

```
gem install fog
```

Example `~/.fog` credentials:

```
 :default:
  :aws_access_key_id:     PERSONAL_ACCESS_KEY
  :aws_secret_access_key: PERSONAL_SECRET
```
To create id_rsa keys:

```
$ ssh-keygen
```

## Boot instance

From Wesley's [fog blog post](http://www.engineyard.com/blog/2011/spinning-up-cloud-compute-instances/ "Spinning Up Cloud Compute Instances | Engine Yard Blog"), boot a vanilla Ubuntu 64-bit image:

``` ruby
$ fog
  Welcome to fog interactive!
  :default provides AWS and VirtualBox
connection = Fog::Compute.new({ :provider => 'AWS', :region => 'us-east-1' })
server = connection.servers.bootstrap({
  :public_key_path => '~/.ssh/id_rsa.pub',
  :private_key_path => '~/.ssh/id_rsa',
  :flavor_id => 'm1.small',
  :bits => 64,
  :username => 'ubuntu'
})
```

[Not using fog?](#not-using-fog)

The rest of the BOSH creation tutorial assumes you used a fog-provided AMI with a user account of `ubuntu`. If you do something different and have a different end experience, please let me know in the Issues.

Check that SSH key credentials are setup. The following should return "ubuntu", and shouldn't timeout.

```
server.ssh("whoami").first.stdout
"ubuntu"
```

Now create an elastic IP and associate it with the instance.

```
address = connection.addresses.create
address.server = server
server.reload
server.dns_name
"ec2-10-2-3-4.compute-1.amazonaws.com"
```

**The public DNS name will be used in the remainder of the tutorials to reference the BOSH VM.**

## Firewall/Security Group

Set your Security Group to include the 25555 port: (the default BOSH director port)

```
group = connection.security_groups.get("default")
group.authorize_port_range(25555..25555)
```

In the AWS console it will look like:

![security groups](https://img.skitch.com/20120414-m9g6ndg3gfjs7kdqhbp2y9a6y.png)

## Prepare for BOSH

Before installing, configuring and running BOSH within our Ubuntu VM, we need to install some prerequisites.

```
$ ssh ubuntu@ec2-10-2-3-4.compute-1.amazonaws.com
sudo su -

export ORIGUSER=ubuntu
curl https://raw.github.com/drnic/bosh-getting-started/master/scripts/prepare_chefbosh.sh | bash
```

## Install BOSH

We will convert the raw Ubuntu VM into a BOSH VM using Chef recipes within the bosh [release](https://github.com/cloudfoundry/bosh/tree/master/release) folder. There is a helper CLI for running chef called [chef_deployer](https://github.com/cloudfoundry/bosh/tree/master/chef_deployer).

Run the following on your local machine. It only creates/modifies a `~/.chefbosh` folder and its contents.

The `prepare_chef_deployer` script creates a `~/.chefbosh/bosh-aws-us-east-1` folder and a `~/.chefbosh/bosh-aws-us-east-1/config.yml` configuration file. The latter is used by bosh's `chef_deployer` CLI to locate and setup the BOSH VM.

```
curl https://raw.github.com/drnic/bosh-getting-started/master/scripts/prepare_chef_deployer > /tmp/prepare_chef_deployer
chmod 755 /tmp/prepare_chef_deployer
export BOSH_GETTING_STARTED='git://github.com/drnic/bosh-getting-started.git -b chefbosh'
export BOSH_PATCH='ssh://$(whoami)@reviews.cloudfoundry.org:29418/bosh refs/changes/35/6935/1'
/tmp/prepare_chef_deployer bosh-aws-us-east-1 aws ACCESS_KEY SECRET_KEY us-east-1 IP_ADDRESS PASSWORD
```

TODO - remove the `BOSH_PATCH`

`IP_ADDRESS` can also be the public DNS for the VM. In this tutorial it is `ec2-10-2-3-4.compute-1.amazonaws.com`.

## Connect to BOSH

We can now connect to our BOSH!

```
$ gem install bosh_cli
$ bosh target ec2-10-2-3-4.compute-1.amazonaws.com:25555
Target set to 'myfirstbosh (http://ec2-10-2-3-4.compute-1.amazonaws.com:25555) Ver: 0.4 (1e5bed5c)'
Your username: admin
Enter password: *****
Logged in as 'admin'
```

Username/password was configured as admin/admin unless you changed it.

If you ask your BOSH a few questions it will tell you the following:

```
$ bosh status
Updating director data... done

Target         yourboshname (http://ec2-10-2-3-4.compute-1.amazonaws.com:25555) Ver: 0.4 (1e5bed5c)
UUID           e28ebc07-3b27-43d7-8219-711498xxxxxx
User           admin
Deployment     not set
~/Projects/gems/bosh/bosh[master]$ bosh releases
No releases
~/Projects/gems/bosh/bosh[master]$ bosh deployments
No deployments
```

Good job.


## Questions

### Not using fog?

Here are a selection of AMIs to use that are [used by the fog](https://github.com/fog/fog/blob/master/lib/fog/aws/models/compute/server.rb#L55-66) example above:

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