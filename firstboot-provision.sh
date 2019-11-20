#!/bin/bash
#
# Provision script for VMs created in VMWare environment
# requires vmtoolsd to be installed (open sourced version preffered -> open-vm-tools)
#
IPREGEXP="^((1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])"
SCRIPT_LOG=/var/log/provision-error.log
SCRIPT_DIR=/usr/share/vmcli/
SERVICE_FILE=firstboot-provision.service

function log_error {
    MSG=$1
    echo "$(date) $MSG" >> $SCRIPT_LOG
    return 0
}

# Gather information about OS distribution and first interface used
DISTRIBUTION=$(egrep '^ID=' /etc/os-release | sed 's/"//g' | awk -F'=' '{print $2}'| tr '[:upper:]' '[:lower:]')
INTERFACE=$(ip link | egrep '^[1-9]:' | grep -v lo: | awk '{print $2}' | sed 's/://')

# Identify proper os family and define destination for network configuration
if [[ $DISTRIBUTION == 'debian' || $DISTRIBUTION == 'ubuntu' ]]
  then
    OSFAMILY='debian'
    INTERFACES_DEST=/etc/network/interfaces
fi

if [[ $DISTRIBUTION == 'redhat' || $DISTRIBUTION == 'centos' ]]
  then
    OSFAMILY='redhat'
    INTERFACES_DEST=/etc/sysconfig/network-scripts/ifcfg-$INTERFACE
fi

# Verify that OS family was properly identified
if [[ -z $OSFAMILY || -z $INTERFACES_DEST ]]
  then
    log_error "Unable to parse OS family from /etc/os-release"
    exit 1
fi

# Check if vmtoolsd binary is present
if [[ ! -x /usr/bin/vmtoolsd ]]
 then
    log_error "No vmtoolsd found installed on the provisioned system"
    exit 1
fi

# Check if we're running on the VM that has provision enabled in VM extra config
PROVISION_ENABLED=$(vmtoolsd --cmd "info-get guestinfo.provision.enabled" 2>&1)

if [[ $PROVISION_ENABLED == 'true' ]]
  then
    # Gather network configuration from VM extra config
    ADDRESS=$(vmtoolsd --cmd "info-get guestinfo.provision.network.address" 2>&1)   
    GATEWAY=$(vmtoolsd --cmd "info-get guestinfo.provision.network.gateway" 2>&1)

    # Save CIDR formatted IP for later ip commands as original may get refromatted
    ADDRESSCIDR=$ADDRESS

    # Verify that parsed IP addresses from extra config are valid
    if [[ ! $ADDRESS =~ $IPREGEXP || ! $GATEWAY =~ $IPREGEXP ]]
      then
        log_error "Unable to parse IP addr or gateway from VM's extra config"
        exit 3
    fi

    # Configure interfaces file
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

    # Temporarily configure interface with required IP address
    ip address flush dev $INTERFACE
    ip address add $ADDRESSCIDR dev $INTERFACE
    ip link set $INTERFACE up
    ip route add default via $GATEWAY
    ping -c 1 $GATEWAY > /dev/null

    # Clean up after self & self
    systemctl disable --quiet $SERVICE_FILE
    rm /etc/systemd/system/$SERVICE_FILE
    rm -r $SCRIPT_DIR
    systemctl daemon-reload

    # Cleanup system (old logs, history, udev rules, tmp files, etc)
    rm /var/log/*.gz /var/log/dmesg.old ~root/.bash_history
    unset HISTFILE
    find /var/log/ -type f -exec sh -c '>"{}"' \;
    > /etc/machine-id
    rm -f /etc/udev/rules.d/70*

else
    log_error "Provision is not explicitly allowed in VM extra config. Exitting..."
    exit 0
fi
