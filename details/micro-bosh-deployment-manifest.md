# Details of Micro BOSH Deployment Manifest

The Micro BOSH Deployment Manifest is simply a subset of a [Deployment Manifest](deployment-manifest.md).

Unlike other deployment manifests, there are only 3 top-level properties (ex. [micro_bosh.yml](../examples/microbosh/micro_bosh.yml)). The Micro BOSH deployment manifest is used when [deploying from the BOSH CLI Deployer](https://github.com/cloudfoundry/oss-docs/blob/master/bosh/documentation/documentation.md), as opposed to using the [Chef installation](../creating-a-bosh-from-scratch.md).

* `name` - expected deployment name
* `networks` - Network information about the Micro BOSH (such as IP, DNS, etc.)
* `cloud` - IaaS properties to be used for this deployment (See AWS API or [vSphere CPI](vsphere-cpi.md))