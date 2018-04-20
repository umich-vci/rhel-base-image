#!/bin/bash -x

#register the system for patches and apply them
subscription-manager register --auto-attach --username=$RHSM_USER --password=$RHSM_PASSWORD
yum -y update

if [ "$PACKER_BUILD_NAME" == "GCP-RHEL7" ]; then
    OS_RELEASE_FILE="/etc/redhat-release"
    if [ ! -f $OS_RELEASE_FILE ]; then
    OS_RELEASE_FILE="/etc/centos-release"
    fi
    DIST=$(cat $OS_RELEASE_FILE | grep -o '[0-9].*' | awk -F'.' '{print $1}')

#Add google yum repository
tee /etc/yum.repos.d/google-cloud.repo << EOM
[google-cloud-compute]
name=Google Cloud Compute
baseurl=https://packages.cloud.google.com/yum/repos/google-cloud-compute-el${DIST}-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg

[google-cloud-sdk]
name=Google Cloud SDK
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el${DIST}-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM

#Configure grub
cat << EOF > /etc/default/grub
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --speed=38400"
GRUB_CMDLINE_LINUX="crashkernel=auto console=ttyS0,38400n8"
GRUB_DISABLE_RECOVERY="true"
EOF

# Configure network
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
BOOTPROTO=dhcp
DEVICE=eth0
ONBOOT=yes
TYPE=Ethernet
DEFROUTE=yes
PEERDNS=yes
PEERROUTES=yes
DHCP_HOSTNAME=localhost
IPV4_FAILURE_FATAL=no
NAME="System eth0"
MTU=1460
PERSISTENT_DHCLIENT="y"
EOF

    # Configure SSH for GCP
    echo "  # Google Compute Engine times out connections after 10 minutes of inactivity." >> /etc/ssh/ssh_conf
    echo "  # Keep alive ssh connections by sending a packet every 7 minutes." >> /etc/ssh/ssh_conf
    echo "	ServerAliveInterval 420" >> /etc/ssh/ssh_conf
    echo "# Compute times out connections after 10 minutes of inactivity.  Keep alive" >> /etc/ssh/sshd_conf
    echo "# ssh connections by sending a packet every 7 minutes." >> /etc/ssh/sshd_conf
    echo "ClientAliveInterval 420" >> /etc/ssh/sshd_conf

    #install packages needed for GCP
    yum -y remove irqbalance
    yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm
    yum -y install python-google-compute-engine,google-compute-engine-oslogin,google-compute-engine,google-cloud-sdk

    #configure NTP for GCP
    #sed -i 's/0.rhel.pool.ntp.org/metadata.google.internal/' /etc/ntp.conf
    #sed -i 's/^server \d\.rhel.pool.ntp.org iburst//g' /etc/ntp.conf
    #systemctl enable ntpd
fi

if [ "$PACKER_BUILD_NAME" == "Azure-RHEL7" ]; then
# Configure network
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
NM_CONTROLLED=no
EOF

cat << EOF > /etc/sysconfig/network
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

    #Disable udev generator for network interfaces
    rm -f /etc/udev/rules.d/75-persistent-net-generator.rules
    ln -s /dev/null /etc/udev/rules.d/75-persistent-net-generator.rules

    #Install the Azure Linux Agent
    subscription-manager repos --enable=rhel-7-server-extras-rpms
    yum -y install WALinuxAgent
    systemctl enable waagent

    #Configure swap on the resource disk
    sed -i 's/^\(ResourceDisk\.EnableSwap\)=[Nn]$/\1=y/g' /etc/waagent.conf
    sed -i 's/^\(ResourceDisk\.SwapSizeMB\)=[0-9]*$/\1=2048/g' /etc/waagent.conf

    #Configure boot arguments
    sed -i 's/^\(GRUB_CMDLINE_LINUX\)=".*"$/\1="crashkernel=auto rootdelay=300 console=ttyS0 earlyprintk=ttyS0 net.ifnames=0"/g' /etc/default/grub

    #Configure sshd
    echo "# Set Azure SSH settings." >> /etc/ssh/sshd_conf
    echo "ClientAliveInterval 180" >> /etc/ssh/sshd_conf
fi

#Rebuild grub to see changes made to the boot arguments
/usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg

#cleanup after patching and unsubscribe system
yum clean all
rm -rf /var/cache/yum
subscription-manager unregister

#lock out the root account
usermod root -p '!!'

if [ "$PACKER_BUILD_NAME" == "Azure-RHEL7" ]; then
    #deprovision the azure agent
    waagent -force -deprovision
fi

#remove udev rules for network card
rm -f /etc/udev/rules.d/70-persistent-net.rules

#delete ssh keys that were generated
rm -f /etc/ssh/ssh_host_*

export HISTSIZE=0
#edit /etc/ssh/sshd_config:s/^PermitRootLogin without-password/PermitRootLogin no/
