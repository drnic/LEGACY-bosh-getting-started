# Deploying the sample release

At the time of writing, there are 4 example BOSH releases. Below is the list and what you deploy with them:

* [cloudfoundry/bosh-sample-release](https://github.com/cloudfoundry/bosh-sample-release) - nginx, wordpress & mysql
* [cloudfoundry/cf-release](https://github.com/cloudfoundry/cf-release) - Cloud Foundry
* [cloudfoundry/oss-release](https://github.com/cloudfoundry/oss-release) - Gerret & Jenkins as [used by CloudFoundry](http://reviews.cloudfoundry.org/ "Gerrit Code Review")
* [cloudfoundry/bosh-release](https://github.com/cloudfoundry/bosh-release) - BOSH itself (inception!)

In this tutorial you will deploy the sample release. It is a 3-tier LAMP application: a wordpress blog which consists of a number of apache servers running php & wordpress, fronted by nginx, and using one mysql database for storage.

## Get the release code

You can get the sample release project using normal `git clone` or using the `gerrit clone` if you think you'll be contributing to the repository:

```
git clone https://github.com/cloudfoundry/bosh-sample-release.git

or

gerrit clone ssh://reviews.cloudfoundry.org:29418/bosh-sample-release.git
```

## Networking provisioning

BOSH can provision VMs and disks. The Deployment Manifest will describe how many VMs/disks are required. BOSH & the deployment manifest cannot provision "an elastic IP address" or a "security group". Rather, IP addresses and security groups must be pre-provisioned and known in advance.

### Elastic IPs

Currently, until BOSH adds DNS support, you'll need IP address per VM that BOSH manages. BOSH can provision and deprovision VMs on its own; yet you need to pre-provision the IP addresses.

In AWS, that's one Elastic IP per managed VM. BOSH will manage the attachment of the IPs to the VMs. You will tell BOSH about the Elastic IPs in your deployment manifest later.

Let's create some with fog into the AWS region that you will be deploying your sample release. These Elastic IPs are different from the one [created with your BOSH](creating-a-bosh-from-scratch.md).

```
$ fog
connection = Fog::Compute.new({ :provider => 'AWS', :region => 'us-east-1' })
addresses = (1..3).map {|i| connection.addresses.create}
addresses.map(&:public_ip)
["23.23.10.10", "23.23.20.10", "23.23.30.10"]
```

Write those down on a Post-it note. You'll need them later. In the initial deployment, your Elastic IPs will be used for nginx, wordpress and mysql VMs, respectively. The example deployment manifest YAML file is populated with the examples above. 

FIXME - find some stupid Post-it notes and insert a picture. This FIXME is not as funny as a real picture of a post-it note.

For simplicity, the examples will assume that IPs in the 23.23.10.XX range are for nginx, 23.23.11.XX are for wordpress, and 23.23.12.XX are for mysql. In reality, you'll get whatever IP addresses that AWS thinks you are worthy of. Keep track of which IPs go with which type of VM on your post-it note or a whiteboard. That's how all sysadmins do this.

### AWS Elastic IPs are scarce

So far in the tutorial we've created 4 Elastic IPs (one for the BOSH and three for this sample release) in the us-east-1 region.

AWS accounts initially restrict each region to 5 Elastic IP addresses. In current BOSH that limits you to 5 VMs per region, which isn't very many. You can [Request to Increase Elastic IP Address Limit](http://aws.amazon.com/contact-us/eip_limit_request/ "Request to Increase Elastic IP Address Limit") and AWS will reply within a few days. 

Perhaps when AWS support IPv6 for Elastic IPs they won't be such a scare resource anymore. 

Better still, when BOSH includes its own DNS then it won't need public Elastic IPs to be able to reference each of the VMs. You'll just need Elastic IPs for any real, public IPs that your deployed environment actually requires. You know, for getting traffic from your customers.

### Security Groups

For this example, we will initially continue to use the pre-existing "default" security group and punch any new holes in it we need.

Specifically you will need to punch the following holes, using the fog console:

```
$ fog
connection = Fog::Compute.new({ :provider => 'AWS', :region => 'us-east-1' })
group = connection.security_groups.get("default")
group.authorize_port_range(8008..8008) # to access wordpress on its VMs
group.authorize_port_range(3306..3306) # to access mysql on its VMs
```

This assumes that port 80 is already open for nginx.

## Sample release

The sample release is already created for us, so "how to create a release" is an activity for a different tutorial. 

```
cd /tmp/microbosh/
git clone https://github.com/cloudfoundry/bosh-sample-release.git
cd bosh-sample-release
cp /tmp/microbosh/bosh-getting-started-on-aws/examples/wordpress/deployment-manifest-initial.yml wordpress-aws.yml
```

If you look at the bosh-sample-release folder you'll see a full BOSH release for an environment. We've also added an AWS-specific manifest for deploying our environment (wordpress-aws.yml).

You'll need to change the `ACCESS_KEY` and `SECRET_ACCESS_KEY` values for your AWS account. This can be a different AWS account from the one used to create your BOSH if you like.

You'll also change `BOSH_AWS_REGISTRY_DNS_NAME` to the domain name of your BOSH. In our tutorial this was `ec2-10-2-3-4.compute-1.amazonaws.com`.

You'll also change `BOSH_DIRECTOR_UUID`

You'll also change the 3 elastic IP addresses (`NGINX_ELASTICIP`, `WORDPRESS_ELASTICIP`, `MYSQL_ELASTICIP`) to the ones that you created.

You'll also change the `WORDPRESS_SERVERNAME` to the public DNS of the elastic IP associated to nginx (ec2-23-23-10-10.compute-1.amazonaws.com in this example).

If you lost your post-it note, get them again with fog:

```
$ fog
connection = Fog::Compute.new({ :provider => 'AWS', :region => 'us-east-1' })
connection.addresses.to_a[-3..-1].map(&:public_ip)
["23.23.10.10", "23.23.20.10", "23.23.30.10"]
```

## Creating the release within BOSH

```
bosh create release
# name it "wordpress"
...

Release version: 1
Release manifest: /private/tmp/microbosh/bosh-sample-release/dev_releases/wordpress-1.yml
```

You can look at this file and see how it explicitly expresses which packages and jobs will be used:

```
cat dev_releases/wordpress-1.yml
```

Confirm that in the manifest for deploying our environment (wordpress-aws.yml) the name is wordpress and version matches the version that was displayed in your terminal (if this is your first release, this will be version 1).

```
cat wordpress-aws.yml
```

Now upload this specific v1 release of "wordpress" to your BOSH. This will upload a big release.tgz to your BOSH.

```
bosh upload release
bosh deployment wordpress-aws.yml
bosh deploy
```

FIXME - suggest that we do this on the BOSH VM so that upload is faster?
FIXME - run the `bosh upload release` at the start of the tutorial; then create all the network bits whilst it uploads
