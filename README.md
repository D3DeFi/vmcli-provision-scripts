Description
-----------

Collection of scripts and files to help with VM provisioning on VMWare virtualization platforms after cloning from template. This is mostly useful when DHCP is out of question and static IP addressing needs to be used. Includes just a very basic network setup to allow for additional configuration via configuration management tools.

Requires vmtools (open-vm-tools recommended) to be installed on the template.

VM extra config is utilized via vmtoolsd --cmd "info-get .." command call. Newly cloned VM needs to have the following directives declared in its extra config:

```
guestinfo.provision.enabled = true
guestinfo.provision.network.address = 10.1.1.2/24
guestinfo.provision.network.gateway = 10.1.1.1
```

Installation
------------

Clone this repo to your template and install systemd service file:

```bash
~$ git clone https://github.com/D3DeFi/vmcli-provision-scripts /usr/share/vmcli  # or use wget/curl
~$ mv /usr/share/vmcli/firstboot-provision.service /etc/systemd/system/firstboot-provision.service
~$ systemctl enable firstboot-provision.service
```
