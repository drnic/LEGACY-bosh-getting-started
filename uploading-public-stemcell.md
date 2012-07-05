# Getting a public stemcell and uploading it

A Stemcell is a VM template with an embedded bosh agent. They are the base image for new VMs. That is, on AWS they are the AMI.

Stemcells are large. 400Mb or more. So, run all the following commands from within your BOSH VM where it will be much faster to download and upload the stemcell to your BOSH.

```
$ ssh ubuntu@ec2-10-2-3-4.compute-1.amazonaws.com
sudo su -
gem install bosh_cli
bosh target localhost:25555
bosh public stemcells
+-------------------------------+-----------------------------------------------------+
| Name                          | Url                                                 |                                                                                                                                       +-------------------------------+-----------------------------------------------------+
| bosh-stemcell-0.4.7.tgz       | https://blob.cfblob.com/rest/objects/4e4e78bc...... |
| bosh-stemcell-aws-0.5.1.tgz   | https://blob.cfblob.com/rest/objects/4e4e78bca..... |
+-------------------------------+-----------------------------------------------------+
```

Patch the aws_cpi: (see https://groups.google.com/a/cloudfoundry.org/group/bosh-users/browse_thread/thread/e53ab0f672bd2ed5/785ad1583496fff3#785ad1583496fff3)
/var/vcap/deploy/bosh/aws_registry/current/aws_cpi/lib/cloud/aws/helpers.rb
needs the patch: http://reviews.cloudfoundry.org/#/c/6507/2/aws_cpi/lib/cloud/aws/helpers.rb

For good measure (please correct this)
I copied it everywhere:
/var/vcap/deploy/bosh/blobstore/current/aws_cpi/lib/cloud/aws/helpers.rb
/var/vcap/deploy/bosh/director/current/aws_cpi/lib/cloud/aws/helpers.rb

You want the latest public AWS stemcell. Download it from the public server and then upload it to your BOSH:

```
$ cd /tmp
$ bosh download public stemcell bosh-stemcell-aws-0.5.1.tgz
bosh-stemcell:  98% |ooooooooooooooooooooooooooooooo  | 384.0MB   1.7MB/s ETA:  00:00:03
```

h3. If you are no in the us-east-1 region
Reference: https://groups.google.com/a/cloudfoundry.org/group/bosh-users/browse_thread/thread/e53ab0f672bd2ed5?pli=1

Now change the manifest unless your bosh is on the EC2_REGION us-east-1
This is because the aki is hardcoded in the manifest of the stemcell
First look for the proper aki on http://cloud.ubuntu.com/ami/
Type the keywords: "EC2_REGION amd64 precise"
And use the aki found there.
For example:
* ap-southeast-1:  aki-aa225af8
* ap-north-east-1: aki-ee5df7ef
* us-west-1:       aki-8d396bc8
To confirm that you are getting the proper aki, "us-east-1 amd64 precise" should return "aki-fe1354ac"

```
tar -xcvf bosh-stemcell-aws-0.5.1.tgz
vim stemcell.MF
# add the
cloud_properties: 
  kernel_id: "aki-fe1354ac"
```
$ bosh upload stemcell bosh-stemcell-aws-0.5.1.tgz
Verifying stemcell...
File exists and readable                                     OK
Manifest not found in cache, verifying tarball...
Extract tarball                                              OK
Manifest exists                                              OK
Stemcell image file                                          OK
Writing manifest to cache...
Stemcell properties                                          OK

Stemcell info
-------------
Name:    bosh-stemcell
Version: 0.5.1

Checking if stemcell already exists...
No

Uploading stemcell...
bosh-stemcell: 100% |ooooooooooooooooooooooooooooooooo | 389.4MB  37.7MB/s Time: 00:00:10
Tracking task output for task#3...

Update stemcell
  extracting stemcell archive (00:00:06)                                                            
  verifying stemcell manifest (00:00:00)                                                            
  checking if this stemcell already exists (00:00:00)                                               
  uploading stemcell bosh-stemcell/0.5.1 to the cloud (00:06:24)                                    
  save stemcell: bosh-stemcell/0.5.1 (ami-a213cbcb) (00:00:00)                                      
Done                    5/5 00:06:30                                                                

Task 3: state is 'done', took 00:06:30 to complete
Stemcell uploaded and created
```

If you look in AWS console, you'll see an AMI created!

![ami](https://img.skitch.com/20120414-gm2jm4g777mjb6xua68aj1kj43.png)

BOSH knows about your uploaded stemcell (an AMI on AWS):

```
$ bosh stemcells

+---------------+---------+--------------+
| Name          | Version | CID          |
+---------------+---------+--------------+
| bosh-stemcell | 0.5.1   | ami-a213cbcb |
+---------------+---------+--------------+
```