# VMware vSphere CPI

The vSphere CPI is used to deploy releases to VMware vSphere clusters. In the deployment manifest, the top-level property `cloud` is used to define the IaaS properties, in this case, vSphere.

Below is a detailed outline of a `cloud` section of a deployment manifest

`
cloud:
  plugin: vsphere
  properties:
    agent:
      ntp:
       - [NTP Server #1]
       - [NTP Server #2]
    vcenters:
      - host: [vCenter Server IP Address]
        user: [Username to login to vCenter with (Ex. "DOMAIN\Username")]
        password: [Password for above account]
        datacenters:
          - name: [Name of Datacenter in vCenter]
            vm_folder: [Folder for VMs]
            template_folder: [Folder for Stemcells]
            disk_path: [Path in datastore to store VMs]
            datastore_pattern: [Pattern to match datastore name(s) (Ex. las01-.*)]
            persistent_datastore_pattern: [Pattern to match datastore name(s) for persistent disks (Ex. las01-.*)]
            allow_mixed_datastores: [False to separate persistent/non-persistent disks, otherwise True]
            clusters:
              - [Name of cluster in above datacenter (Ex. CLUSTER01)]
				resource_pool: [Optional: Resource pool to store VMs]
`



## Preparing vSphere for deployments

There is a tiny bit of prep work that needs to be done before deployments can be made to vSphere. This is documented in VMware's [oss-docs](https://github.com/cloudfoundry/oss-docs/blob/master/bosh/documentation/documentation.md), but just for clarification:

* Create a folder in "VMs and Templates" to match `vm_folder`
* Create a folder in "VMs and Templates" to match `template_folder`
* Create the `disk_path` in all datastores that match the patterns in `datastore_pattern` and `persistent_datastore_pattern`
* If `resource_pool` is defined, create the resource pool
* The `user` account must be created and granted the proper permissions in vCenter. See: VMware's [oss-docs](https://github.com/cloudfoundry/oss-docs/blob/master/bosh/documentation/documentation.md) under "vCenter Configuration"

Once this is done, the vSphere CPI may be used to deploy releases

