#!/bin/bash
IFS=$'\n'
# # Install deps
# Ubuntu packages
[ -x "$(which apt-get)" ] && export DEBIAN_FRONTEND=noninteractive && apt-get -o Acquire::ForceIPv4=true -qq update && apt-get install -o Acquire::ForceIPv4=true -qq -y wget curl jq qemu-guest-agent unzip python3-pyudev python3-boto3 python3-retrying
[ ! -x "$(which yq)" ] && wget -q https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq

# # Setup zCompute pre-reqs
# Install AWS CLI
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip -qq awscliv2.zip && sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && rm awscliv2.zip && rm -r /aws
# # Setup adjustments to support EBS CSI
[ ! -e /etc/udev/rules.d/zadara_disk_mapper.rules ] && wget -q -O /etc/udev/rules.d/zadara_disk_mapper.rules https://raw.githubusercontent.com/zadarastorage/zadara-examples/f1cc7d1fefe654246230e544e2bea9b63329be42/k8s/eksd/eksd-packer/files/zadara_disk_mapper.rules
[ ! -e /usr/bin/zadara_disk_mapper.py ] && wget -q -O /usr/bin/zadara_disk_mapper.py https://raw.githubusercontent.com/zadarastorage/zadara-examples/f1cc7d1fefe654246230e544e2bea9b63329be42/k8s/eksd/eksd-packer/files/zadara_disk_mapper.py
chmod 755 /usr/bin/zadara_disk_mapper.py
[ -e /lib/udev/rules.d/66-snapd-autoimport.rules ] && rm /lib/udev/rules.d/66-snapd-autoimport.rules
[ -e /lib/systemd/system/systemd-udevd.service ] && sed -i '/IPAddressDeny=any/d' /lib/systemd/system/systemd-udevd.service && systemctl daemon-reload && systemctl restart systemd-udevd && udevadm control --reload-rules && udevadm trigger # TODO Add to whitelist instead of removing Deny rule...

# Disable firewalls
[ -x "$(which ufw)" ] && ufw disable && systemctl disable ufw && systemctl stop ufw

# CNI Network plugins, may be needed by some CNIs
mkdir -p /opt/cni/bin
curl -s -O -L https://github.com/containernetworking/plugins/releases/download/v1.6.0/cni-plugins-linux-amd64-v1.6.0.tgz && tar -C /opt/cni/bin -xzf cni-plugins-linux-amd64-v1.6.0.tgz && rm cni-plugins-linux-amd64-v1.6.0.tgz
