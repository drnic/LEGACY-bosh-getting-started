These instructions are a combination of "Boot an AWS instance" and "Install BOSH via its chef_deployer"

Follow along with [this 16 min screencast](https://vimeo.com/40484383).

* Create a VM
* Run prepare_instance.sh inside instance
* From your dev box, use chef_deployer to setup the VM as BOSH over ssh

## Setup

Install fog, \~/.fog credentials (for AWS), and \~/.ssh/id_rsa(.pub) keys

Install fog

```
gem install fog
```

Example \~/.fog credentials:

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

```
$ fog
  Welcome to fog interactive!
  :default provides AWS and VirtualBox
connection = Fog::Compute.new({ :provider => 'AWS', :region => 'us-east-1' })
server = connection.servers.bootstrap({
  :public_key_path => '~/.ssh/id_rsa.pub',
  :private_key_path => '~/.ssh/id_rsa',
  :flavor_id => 'm1.large', # 64 bit, normal large
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

Note: as of June 2012, VPC is not yet supported by bosh (see [mail exchanges](https://groups.google.com/a/cloudfoundry.org/group/bosh-dev/browse_thread/thread/30ca9b70b23fa4e7) ), so best to stick with an EC2 instance for now.

The rest of the BOSH creation tutorial assumes you used a fog-provided AMI with a user account of `ubuntu`. If you do something different and have a different end experience, please let me know in the Issues.

Check that SSH key credentials are setup. The following should return "ubuntu", and shouldn't timeout.

```
server.ssh "whoami"
```

Now create an elastic IP and associate it with the instance. (I did this via the console).

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

Alternately, run it inside screen or tmux so you don't have to fear early termination:

Update the system with security updates and patches (e.g. avoid bug in ubuntu prevents instance reboot)
```
sudo apt-get dist-upgrade
```

```
$ ssh ubuntu@ec2-10-2-3-4.compute-1.amazonaws.com
sudo su -
groupadd vcap 
useradd vcap -m -g vcap

mkdir -p /var/vcap/
cp /home/ubuntu/.ssh/authorized_keys /var/vcap/

vim /etc/apt/sources.list
```

Add the following line. **If you're in a different AWS region, change the URL prefix.**

```
deb http://us-east-1.ec2.archive.ubuntu.com/ubuntu/ lucid multiverse
```

Back in the remote terminal (you can copy and paste each chunk):

```
apt-get update
apt-get install git-core -y

mkdir /var/vcap/bootstrap
cd /var/vcap/bootstrap
git clone https://github.com/cloudfoundry/bosh.git
cd bosh/release/template/instance
./prepare_instance.sh

chmod 777 /var/vcap/deploy
```

Postgresql db is configured to run with en_US.UTF-8 locale that needs to be present in your EC2 instance. Add it if missing.

```
#check if en_US.UTF-8 locale is indeed available in your system
locale -a
#if not add it, otherwise pgresql will refuse to start complaining about invalid lc_message with "en_US.UTF-8"
locale-gen en_US.UTF-8 
exit
```

**From another terminal on your local machine:**

We'll now configure over SSH the VM we've prepared using chef.
Your local machine should have [github ssh certificates installed](https://help.github.com/articles/generating-ssh-keys) and ruby, rubygems installed (e.g. reuse prepare_instance.sh commands)

Make a copy of the `examples/microbosh` folder contents and add your AWS credentials as appropriate into `config.yml`:

```
mkdir -p ~/.microbosh
chmod 700 ~/.microbosh
cd ~/.microbosh

git clone git://github.com/drnic/bosh-getting-started.git
cp -r bosh-getting-started/examples/microbosh/* .
vim config.yml
```

* replace all `PUBLIC_DNS_NAME` with your fog-created VM's `server.dns_name` (e.g. ec2-10-2-3-4.compute-1.amazonaws.com)
* replace `ACCESS_KEY_ID` with your AWS access key id
* replace `SECRET_ACCESS_KEY` with your AWS secret access key
* replace value of ec2_endpoint with the EC2 endpoint for the region you use

In VIM, you can "replace all" by typing:

```
:%s/PUBLIC_DNS_NAME/ec2-10-2-3-4.compute-1.amazonaws.com/g
```

We'll now use chef to install and start all the parts of BOSH. The `chef_deployer` subfolder of BOSH orchestrates this.

Get the chef_deployer & cookbooks (all from the same [bosh](https://github.com/cloudfoundry/bosh) repository) and we're almost done!

```
cd ~/.microbosh
git clone https://github.com/cloudfoundry/bosh.git
cd bosh/chef_deployer
bundle
cd ../release/
```

Now we can run chef to install BOSH:

```
ruby ../chef_deployer/bin/chef_deployer deploy ~/.microbosh
...lots of chef...
```

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

As of july 6th 2012, there are two patches that are not yet merged into the bosh repo that you may want to apply, especially if you're not running your bosh instance on the default us-west-1c availability zone.

First, manually get a patch for http://reviews.cloudfoundry.org/#/c/6507/

```
diff /var/vcap/bootstrap/bosh/aws_cpi/lib/cloud/aws/helpers.rb /var/vcap/bootstrap/bosh/aws_cpi/lib/cloud/aws/helpers.rb.orig
23d22
<       failures = 0
38,50c37
<         begin
<           state = resource.send(state_method)
<         rescue AWS::EC2::Errors::InvalidAMIID::NotFound => e
<           # ugly workaround for an AWS issue:
<           # sometimes when we upload a stemcell and proceed to create a VM from
<           # it, AWS reports that the AMI is missing, but checking the console
<           # it is there, so by retrying we catch that race condition
<           raise e if failures > 3
<           failures =+ 1
<           @logger.error("AMI not found: #{desc}")
<           sleep(1)
<           next
<         end
---
>         state = resource.send(state_method)
74d60
<
```

then modify the /var/vcap/deploy/bosh/aws_registry/shared/config/aws_registry.yml config file to add the "ec2_endpoint" property to the aws hash.



Good job.

