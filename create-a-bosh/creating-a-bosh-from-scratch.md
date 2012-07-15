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
  :flavor_id => 'm1.medium', # 64 bit, normal medium
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

## Install BOSH

These commands below can take a long time. If it terminates early, re-run it until completion.

Alternately, run it inside screen or tmux so you don't have to fear early termination.

NOTE: see $REGION set to `us-east-1` below. Change as appropriate.

```
$ ssh ubuntu@ec2-10-2-3-4.compute-1.amazonaws.com
sudo su -

branch="create-user"
curl https://raw.github.com/drnic/bosh-getting-started/${branch}/scripts/create_vcap_user.sh | bash

mkdir -p /var/vcap
cp /home/ubuntu/.ssh/authorized_keys /var/vcap/

az=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
region=${az:0:${#az}-1} # remove last character of $az

echo BOSH located in region ${region} in AZ ${az}
echo "deb http://${region}.ec2.archive.ubuntu.com/ubuntu/ lucid multiverse" >> /etc/apt/sources.list
# curl https://raw.github.com/cloudfoundry/bosh/master/release/template/instance/prepare_instance.sh | bash
curl https://raw.github.com/drnic/bosh/prepare_chef_deployer/release/template/instance/prepare_instance.sh | bash
```

**From another terminal on your local machine:**

Make a copy of the `examples/chefbosh` folder contents and add your AWS credentials as appropriate into `config.yml`:

```
mkdir -p ~/.chefbosh
chmod 700 ~/.chefbosh
cd ~/.chefbosh

git clone git://github.com/drnic/bosh-getting-started.git
cp -r bosh-getting-started/examples/chefbosh/* .
vim config.yml
```

* replace all `PUBLIC_DNS_NAME` with your fog-created VM's `server.dns_name` (e.g. ec2-10-2-3-4.compute-1.amazonaws.com)
* replace `ACCESS_KEY_ID` with your AWS access key id
* replace `SECRET_ACCESS_KEY` with your AWS secret access key

In VIM, you can "replace all" by typing:

```
:%s/PUBLIC_DNS_NAME/ec2-10-2-3-4.compute-1.amazonaws.com/g
```

We'll now use chef to install and start all the parts of BOSH. The `chef_deployer` subfolder of BOSH orchestrates this.

Get the chef_deployer & cookbooks (all from the same [bosh](https://github.com/cloudfoundry/bosh) repository) and run chef upon your VM.

```
cd ~/.chefbosh
git clone https://github.com/cloudfoundry/bosh.git
cd bosh/chef_deployer

bundle
cd ../release/
ruby ../chef_deployer/bin/chef_deployer deploy ~/.chefbosh --default-password=''
...lots of chef...
```

Now apply patches to BOSH CLI:

```
# need fix for https://cloudfoundry.atlassian.net/browse/CF-71
# http://reviews.cloudfoundry.org/#/c/7086/
git fetch ssh://$(whoami)@reviews.cloudfoundry.org:29418/bosh refs/changes/86/7086/1 && git cherry-pick FETCH_HEAD
cd ~/.chefbosh/bosh/cli
bundle install --without=development test
rake install
```

When no patches are necessary to the BOSH CLI, it can be installed from RubyGems:

```
gem install bosh_cli
```

Now target your BOSH from the CLI:

```
$ bosh target ec2-10-2-3-4.compute-1.amazonaws.com:25555
Target set to 'myfirstbosh (http://ec2-10-2-3-4.compute-1.amazonaws.com:25555) Ver: 0.4 (1e5bed5c)'
Your username: admin
Enter password: *****
Logged in as 'admin'
```

Username/password defaults to `admin/admin`. Please change it immediately.

## Administration

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

## Status

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

