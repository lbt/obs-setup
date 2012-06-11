#!/bin/bash

# Mer Delivery System host:port
MDS="mer.dgreaves.com:8001"
VMS="obsfe:fe obsbe:be obsw1:worker"

obsuser=obsuser

. setup-obs.conf

if [[ $UID -ne 0 ]]; then echo "$0 must be run as root"; exit 1; fi

for v in $VMS; do
    # split v into vm/role
    IFS=":" read -r vm role DUMMY <<< "$v"
    echo "Setting up $vm as $role based on $v"

    # Tidy up: remove the old VMs
    (virsh --connect qemu:///system destroy $vm
	sleep 1
	/maemo/devel/mk_vm/mk_suse_vm $vm
	sleep 5
	while ! ssh -o CheckHostIP=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$vm true 2>/dev/null ; do
	    sleep 1
	done
	echo "$vm is up... starting install as $role"
	scp -o CheckHostIP=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null setup-obs.sh setup-obs.conf root@$vm:.
	ssh -o CheckHostIP=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$vm ./setup-obs.sh $role) &
done

# Allow installs and setups to complete
wait

echo "All VM setup done - starting tests"

sleep 10

## Connect MDS

su - ${obsuser} -c $(pwd)/setup-mds.sh
