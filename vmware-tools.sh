#!/bin/bash -x

mount -t iso9660 -o loop /root/linux.iso /media
cd /tmp
cp /mnt/VMwareTools-*.gz .
umount /media
rm -f /root/linux.iso
tar xf VMwareTools-*.gz
./vmware-tools-distrib/vmware-install.pl -d
rm -rf VMwareTools-*.gz vmware-tools-distrib