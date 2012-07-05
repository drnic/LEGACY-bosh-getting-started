# Deploying the sample release

At the time of writing, there are 4 example BOSH releases. Below is the list and what you deploy with them:

* [cloudfoundry/bosh-sample-release](https://github.com/cloudfoundry/bosh-sample-release) - nginx, wordpress & mysql
* [cloudfoundry/cf-release](https://github.com/cloudfoundry/cf-release) - Cloud Foundry
* [cloudfoundry/oss-release](https://github.com/cloudfoundry/oss-release) - Gerret & Jenkins as [used by CloudFoundry](http://reviews.cloudfoundry.org/ "Gerrit Code Review")
* [cloudfoundry/bosh-release](https://github.com/cloudfoundry/bosh-release) - BOSH itself (inception!)

In this tutorial you will deploy the sample release. It is a 3-tier LAMP application: a wordpress blog which consists of a number of apache servers running php & wordpress, fronted by nginx, and using one mysql database for storage.

## Working area

```
mkdir -p ~/.bosh_deployments/wordpress
cd ~/.bosh_deployments/wordpress
```

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

Currently, until BOSH adds DNS support, you'll need one IP address per VM so that each job within the release can reference the other VMs.

BOSH can provision and deprovision VMs on its own; but you need to pre-provision the IP addresses.

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

For simplicity, this tutorial will assume that IPs in the 23.23.10.XX range are for nginx, 23.23.11.XX are for wordpress, and 23.23.12.XX are for mysql. In reality, you'll get whatever IP addresses that AWS thinks you are worthy of. Keep track of which IPs go with which type of VM on your post-it note or a whiteboard. That's how all sysadmins do it.

### AWS Elastic IPs are scarce

So far in the tutorial we've created 4 Elastic IPs (one for the BOSH and three for this sample release) in the us-east-1 region.

AWS accounts initially restrict each region to 5 Elastic IP addresses. In current BOSH that limits you to 5 VMs per region, which isn't very many. You can [Request to Increase Elastic IP Address Limit](http://aws.amazon.com/contact-us/eip_limit_request/ "Request to Increase Elastic IP Address Limit") and AWS will reply within a few days. 

Perhaps when AWS support IPv6 for Elastic IPs they won't be such a scare resource anymore. 

Better still, when BOSH includes its own DNS then it won't need public Elastic IPs to be able to reference each of the VMs. You'll only need Elastic IPs for any real, public IPs that your deployed environment actually requires. You know, for getting traffic from your customers.

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

This assumes that port 80 is already open for nginx on its VM.

As an experiment for you, dear reader, try creating three separate security groups with only the required ports open for the nginx VM (port 80), wordpress (port 8008), and mysql (port 3306) and update your deployment manifest.

## Sample release

The sample release is already created for us, so "how to create a release" is an activity for a different tutorial. 

```
cd ~/.bosh_deployments/wordpress
cp ~/.microbosh/bosh-getting-started/examples/wordpress/deployment-manifest-initial.yml wordpress-aws.yml
```

If you look at the bosh-sample-release folder you'll see a full BOSH release for an environment. We've also added an AWS-specific manifest for deploying our environment (wordpress-aws.yml).

For deploying BOSH, you'll need to change the `ACCESS_KEY` and `SECRET_ACCESS_KEY` values for your AWS account. This can be a different AWS account from the one used to create your BOSH if you like. You'll also change `BOSH_AWS_REGISTRY_DNS_NAME` to the domain name of your BOSH. In our tutorial this was `ec2-10-2-3-4.compute-1.amazonaws.com`.

For deploying wordpress, you'll merely start wth changing `BOSH_DIRECTOR_UUID` with the value from running `bosh status`, and using the `UUID` value. If you're not running on the default availability zone (us-east-1a) , then specify the "availability_zone" property in the common resource pool, as well as in the compilation section. For manually connecting to the instances, you may want to specify the "key_name" property to one of your EC2 key pairs.

FUTURE - You'll also change the 3 elastic IP addresses (`NGINX_ELASTICIP`, `WORDPRESS_ELASTICIP`, `MYSQL_ELASTICIP`) to the ones that you created.

You'll also change the `WORDPRESS_SERVERNAME` to the public DNS of the elastic IP associated to nginx (ec2-23-23-10-10.compute-1.amazonaws.com in this example).

If you lost your post-it note, get them again with fog:

```
$ fog
connection = Fog::Compute.new({ :provider => 'AWS', :region => 'us-east-1' })
connection.addresses.to_a[-3..-1].map(&:public_ip)
["23.23.10.10", "23.23.20.10", "23.23.30.10"]
```

## Creating the release within BOSH

Lets move our draft wordpress.yml into the release template, commit it into git (so that it gets archived with other parts of the release, such as source code)

```
cd ~/.bosh_deployments/wordpress/bosh-sample-release
cp ../wordpress-aws.yml wordpress.yml
git commit -a

$ bosh create release
# name it "wordpress"
...

Release version: 1
Release manifest: ~/.bosh_deployments/wordpress/bosh-sample-release/dev_releases/wordpress-1.1-dev.yml
```

You can look at this file and see how it explicitly expresses which packages and jobs will be used. You'll see that a total of 6 packages are installed and 3 jobs will be managed (nginx, wordpress and mysql).

```
cat dev_releases/wordpress-1.yml
```

This specific combination of package and jobs is called "development release 1".

Confirm that in the manifest for deploying our environment (wordpress-aws.yml) the name is wordpress and version matches the version that was displayed in your terminal (if this is your first release, this will be version 1).

```
cat wordpress-aws.yml
```

The BOSH doesn't know about our release yet. We need to upload it. This involves generating a gzipped tarball (release.tgz), uploading it, and then compiling the packages. In this example, the tarball contains the gzipped source for our 6 packages and the descriptions of the jobs. It totals about 63MB.

```
$ bosh upload release
```

* FIXME - run the `bosh upload release` at the start of the tutorial; then create all the network bits whilst it uploads

Uploading the release can be slow if you do it from your local home machine or your laptop on the train. 63Mb never felt so slow.

Also slow is compiling packages and provisioning AWS VMs, which is what we're now ready to do! That is, we are finally ready to deploy our environment release!

This will initially take some additional time to compile all the packages into binaries. It does this by booting dedicated VMs for performing compilation. Compiling packages is only required when a package is changed as part of a new release upload.

TODO - how to reuse VMs for compilation

By default, it boots a single VM per package to ensure a clean environment. On AWS using an m1.small, this means you'll pay 8c per package (the minimum hourly price). We have 6 packages. My 5 year old cannot do multiplication but my calculator can. That's 48c to compile your packages.

Now tell the BOSH CLI which deployment we care about using `bosh deployment MANIFEST_FILE`. This is akin to `bosh target DIRECTOR` which tells BOSH CLI which director to focus on. BOSH CLI is optimized for your workflow - you'll be working on a single deployment/release on a single BOSH director.

```
$ bosh deployment ../wordpress-aws.yml
Deployment set to '/private/tmp/microbosh/wordpress/bosh-sample-release/wordpress-aws.yml'
$ bosh deploy
Getting deployment properties from director...
Unable to get properties list from director, trying without it...
Compiling deployment manifest...
Cannot get current deployment information from director, possibly a new deployment
Please review all changes carefully
Deploying `wordpress-aws.yml' to `yourboshname' (type 'yes' to continue): yes
Tracking task output for task#16...

Preparing deployment
  binding deployment (00:00:00)                                                                     
  binding release (00:00:00)                                                                        
  binding existing deployment (00:00:00)                                                            
  binding resource pools (00:00:00)                                                                 
  binding stemcells (00:00:00)                                                                      
  binding templates (00:00:00)                                                                      
  binding unallocated VMs (00:00:00)                                                                
  binding instance networks (00:00:00)                                                              
Done                    7/7 00:00:00                                                                

Compiling packages
  wordpress/0.1-dev (00:02:52)                                                                      
  mysql/0.1-dev (00:03:10)                                                                          
  mysqlclient/0.1-dev (00:02:50)                                                                    
  nginx/0.1-dev (00:05:08)                                                                          
  apache2/0.1-dev (00:12:27)                                                                        
php5/0.1-dev                        |oooooooooooooooooooo    | 5/6 00:16:22  ETA: --:--:--```
```

During the compilation process, if you check AWS console you'll notice that VMs are being provisioned and deprovisioned.

![worker vms in action](https://img.skitch.com/20120416-8s7ymaj5ygnpyydbfysbr1r4r2.png)

In our example they are provisioned in pairs of `m1.small` instances. Why? Our deployment manifest told BOSH to do this:

```yaml
compilation:
  workers: 2
  network: default
  cloud_properties:
    disk: 8096
    instance_type: m1.small
```

When all the packages are compiled, the AWS console will show a list of 6 VMs that were used for the packages:

![worker vms](https://img.skitch.com/20120416-g8jnht1wcag84ker3pn1fe8i9w.png)

After package compilation, BOSH begins booting the VMs you require. For our deployment we've asked for three `m1.small` instances; one for `nginx`, `wordpress` and `mysql` jobs.   

After completion, you can see the status of your current target deployment:

```
$ bosh status
Updating director data... done

Target         yourboshname (http://ec2-10-2-3-4.compute-1.amazonaws.com:25555) Ver: 0.4 (6122358b)
UUID           e28ebc07-3b27-43d7-8219-XXXXXXXXX
User           drnic
Deployment     /private/tmp/microbosh/bosh-sample-release/wordpress-aws.yml

You are in release directory
----------------------------
Dev name:      wordpress
Dev version:   1

Final name:    sample
Final version: 1

Packages
+-------------+----------+----------+
| Name        | Dev      | Final    |
+-------------+----------+----------+
| apache2     |      0.1 |      n/a |
| mysql       |      0.1 |      n/a |
| mysqlclient |      0.1 |      n/a |
| nginx       |      0.1 |      n/a |
| php5        |      0.1 |      n/a |
| wordpress   |      0.1 |      n/a |
+-------------+----------+----------+

Jobs
+-----------+----------+----------+
| Name      | Dev      | Final    |
+-----------+----------+----------+
| mysql     |      0.1 |      n/a |
| nginx     |      0.1 |      n/a |
| wordpress |      0.1 |      n/a |
+-----------+----------+----------+
```
