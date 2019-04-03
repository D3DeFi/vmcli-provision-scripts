#!/bin/bash
#
# Provision script for VMs created in VMWare environment
# requires vmtoolsd to be installed (open sourced version preffered -> open-vm-tools)
#
IPREGEXP="^((1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])"
SCRIPT_LOG=/var/log/provision-error.log
SCRIPT_DIR=/usr/share/vmcli/
SERVICE_FILE=firstboot-provision.service

# Gather information about OS distribution and first interface used
DISTRIBUTION=$(egrep '^ID=' /etc/os-release | sed 's/"//g' | awk -F'=' '{print $2}'| tr '[:upper:]' '[:lower:]')
INTERFACE=$(ip link | egrep '^[1-9]:' | grep -v lo: | awk '{print $2}' | sed 's/://')

# Identify proper os family and define destination for network configuration
if [[ $DISTRIBUTION == 'debian' || $DISTRIBUTION == 'ubuntu' ]]
  then
    OSFAMILY='debian'
    INTERFACES_DEST=/etc/network/interfaces
    NETWORK_SERVICE=networking.service
fi

if [[ $DISTRIBUTION == 'redhat' || $DISTRIBUTION == 'centos' ]]
  then
    OSFAMILY='redhat'
    INTERFACES_DEST=/etc/sysconfig/network-scripts/ifcfg-$INTERFACE
    NETWORK_SERVICE=network.service
fi

if [[ -z $OSFAMILY || -z $INTERFACES_DEST ]]
  then
    echo "Unable to parse OS family" >> $SCRIPT_LOG
    exit 1
fi

# Ensure vmtoolsd binary is present
if [[ $(whereis vmtoolsd | awk '{print $2}') == "" ]]
 then
    echo "No vmtoolsd found on system" >> $SCRIPT_LOG
    exit 1
fi

# Check if we're running on the VM that has provision enabled in VM extra config
PROVISION_ENABLED=$(vmtoolsd --cmd "info-get guestinfo.provision.enabled" 2>&1)

if [[ $PROVISION_ENABLED == 'true' ]]
  then
    # Gather network configuration from VM extra config
    ADDRESS=$(vmtoolsd --cmd "info-get guestinfo.provision.network.address" 2>&1)   
    GATEWAY=$(vmtoolsd --cmd "info-get guestinfo.provision.network.gateway" 2>&1)

    if ! echo $ADDRESS | egrep -qE $IPREGEXP || ! echo $GATEWAY | egrep -qE $IPREGEXP
      then
        echo "Unable to parse IP addr or gateway from VM extra config" >> $SCRIPT_LOG
        exit 3
    fi

    # Configure interfaces file
    systemctl stop $NETWORK_SERVICE
    cp $SCRIPT_DIR/templates/network-$OSFAMILY.template $INTERFACES_DEST

    # RedHat systems requires an additional information
    if [[ $OSFAMILY == 'redhat' ]]
      then
        UUID=$(uuidgen $INTERFACE)
        CIDR=$(echo $ADDRESS | awk -F '/' '{print $2}')    
        ADDRESS=${ADDRESS%/*}

        sed -i "s#\${UUID}#$UUID#g" $INTERFACES_DEST
        sed -i "s#\${CIDR}#$CIDR#g" $INTERFACES_DEST
    fi
   
    # Replace required variables inside interfaces file 
    # sed is using # as delimiter due to / being present in ADDRESS
    sed -i "s#\${INTERFACE}#$INTERFACE#g" $INTERFACES_DEST
    sed -i "s#\${ADDRESS}#$ADDRESS#g" $INTERFACES_DEST
    sed -i "s#\${GATEWAY}#$GATEWAY#g" $INTERFACES_DEST

    systemctl start $NETWORK_SERVICE

    # Clean up after self & self
    systemctl disable $SERVICE_FILE
    rm /etc/systemd/system/$SERVICE_FILE
    rm -r $SCRIPT_DIR
    systemctl daemon-reload

    # Clean old logs and history
    > /root/.bash_history

else
    # Provision is not explicitly allowed in VM extra config
    exit 2
fi