# Troubleshooting - Cloud consistency check and interactive repair

Bosh provides an utility to check cloud consistency and, in some situations, can repair problems automatically.

You can invoke the utility via the `cloudcheck` (or `cck`) bosh command:

```
$ bosh help
...
cloudcheck                Cloud consistency check and interactive repair
                          --auto     resolve problems automatically (not
                                     recommended for production)
                          --report   generate report only, don't attempt
                                     to resolve problems
...
```

## Cloud consistency checks

The utility scans VMs and Disks looking for:

* Agents unresponsive
* Disks inactive
* Disks mount info mismatch
* VMs out of sync
* VMs unbound

## Interactive repair

```
$ bosh cck
Performing cloud check...

Scanning 1 VMs
  checking VM states (00:00:10)
  0 OK, 1 unresponsive, 0 unbound, 0 out of sync (00:00:00)
Done                    2/2 00:00:10

Scanning 0 persistent disks
  looking for inactive disks (00:00:00)
  0 OK, 0 inactive, 0 mount-info mismatch (00:00:00)
Done                    2/2 00:00:00
Scan is complete, checking if any problems found...

Found 1 problem

Problem 1 of 1: Problem (unresponsive_agent 1) is no longer valid: VM `1' doesn't have a cloud id.
  1. Close problem
Please choose a resolution [1 - 1]: 1

Below is the list of resolutions you've provided
Please make sure everything is fine and confirm your changes

  1. Problem (unresponsive_agent 1) is no longer valid: VM `1' doesn't have a cloud id
     Close problem

Apply resolutions? (type 'yes' to continue): yes
Applying resolutions...

Applying problem resolutions
  unresponsive_agent 1: Close problem (00:00:00)

Done                    1/1 00:00:00
```