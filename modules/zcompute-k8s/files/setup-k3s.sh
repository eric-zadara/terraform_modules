#!/bin/bash
IFS=$'\n'
# Ensure no race condition for configuration file
until [ -e /etc/zadara/k8s.json ]; do sleep 1s ; done
# # Install deps
# Ubuntu packages
[ -x "$(which apt-get)" ] && export DEBIAN_FRONTEND=noninteractive && apt-get -o Acquire::ForceIPv4=true -qq update && apt-get install -o Acquire::ForceIPv4=true -qq -y wget curl jq qemu-guest-agent unzip python3-pyudev python3-boto3 python3-retrying

# Read configuration
CLUSTER_NAME="$(jq -c --raw-output '.cluster_name' /etc/zadara/k8s.json)"
CLUSTER_ROLE="$(jq -c --raw-output '.cluster_role' /etc/zadara/k8s.json)"
CLUSTER_VERSION="$(jq -c --raw-output '.cluster_version' /etc/zadara/k8s.json)"
CLUSTER_KAPI="$(jq -c --raw-output '.cluster_kapi' /etc/zadara/k8s.json)"
FEATURE_GATES="$(jq -c --raw-output '.feature_gates' /etc/zadara/k8s.json)"
NODE_LABELS=( $(jq -c --raw-output '.node_labels | to_entries[] | .key + "=" + .value' /etc/zadara/k8s.json | sort) )
NODE_TAINTS=( $(jq -c --raw-output '.node_taints | to_entries[] | .key + "=" + .value' /etc/zadara/k8s.json | sort) )
export K3S_TOKEN="$(jq -c --raw-output '.cluster_token' /etc/zadara/k8s.json)"
export K3S_NODE_NAME=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

[ -n "${CLUSTER_VERSION}" ] && [ "${CLUSTER_VERSION}" != "null" ] && export INSTALL_K3S_VERSION="v${CLUSTER_VERSION}+k3s1"

# Functions
_log() { echo "[$(date +%s)][$0]${@}" ; }
_gate() { jq -e -c --raw-output --arg element "${1}" 'any(.[];.==$element)' <<< ${FEATURE_GATES} > /dev/null 2>&1; }
wait-for-endpoint() {
	# $1 should be http[s]://<target>:port
	SLEEP=${SLEEP:-1}
	until curl -k --head -s -o /dev/null "${1}" > /dev/null 2>&1; do
		sleep ${SLEEP}s
		[ $SLEEP -lt 10 ] && SLEEP=$((SLEEP + 1))
		[ $SLEEP -ge 10 ] && _log "[wait-for-endpoint] Waiting ${SLEEP}s for ${1}"
	done
}
wait-for-instance-profile() {
	SLEEP=${SLEEP:-1}
	while :; do
		PROFILE_NAME=$(curl --fail -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
		[ $? -eq 0 ] && [ -n "${PROFILE_NAME:-}" ] && break
		sleep ${SLEEP}s
		[ $SLEEP -lt 10 ] && SLEEP=$((SLEEP + 1))
		[ $SLEEP -ge 10 ] && _log "[wait-for-instance-profile] Waiting ${SLEEP}s for profile name"
	done
	
	while ! curl -k --fail -s -o /dev/null http://169.254.169.254/latest/meta-data/iam/security-credentials/${PROFILE_NAME} > /dev/null 2>&1; do
		sleep ${SLEEP}s
		[ $SLEEP -lt 10 ] && SLEEP=$((SLEEP + 1))
		[ $SLEEP -ge 10 ] && _log "[wait-for-instance-profile] Waiting ${SLEEP}s for profile contents"
	done
}

# # Setup zCompute pre-reqs
# Install AWS CLI
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip -qq awscliv2.zip && sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && rm awscliv2.zip && rm -r /aws
# # Setup adjustments to support EBS CSI
[ ! -e /etc/udev/rules.d/zadara_disk_mapper.rules ] && wget -O /etc/udev/rules.d/zadara_disk_mapper.rules https://raw.githubusercontent.com/zadarastorage/zadara-examples/f1cc7d1fefe654246230e544e2bea9b63329be42/k8s/eksd/eksd-packer/files/zadara_disk_mapper.rules
[ ! -e /usr/bin/zadara_disk_mapper.py ] && wget -O /usr/bin/zadara_disk_mapper.py https://raw.githubusercontent.com/zadarastorage/zadara-examples/f1cc7d1fefe654246230e544e2bea9b63329be42/k8s/eksd/eksd-packer/files/zadara_disk_mapper.py
chmod 755 /usr/bin/zadara_disk_mapper.py
[ -e /lib/udev/rules.d/66-snapd-autoimport.rules ] && rm /lib/udev/rules.d/66-snapd-autoimport.rules
[ -e /lib/systemd/system/systemd-udevd.service ] && sed -i '/IPAddressDeny=any/d' /lib/systemd/system/systemd-udevd.service # TODO Add to whitelist instead of removing Deny rule...
[ $? -eq 0 ] && [ -e /lib/systemd/system/systemd-udevd.service ] && systemctl daemon-reload && systemctl restart systemd-udevd && udevadm control --reload-rules && udevadm trigger

# # Setup k3s adjustments
ln -s /var/lib/rancher/k3s/agent/etc/containerd/ /etc/containerd
ln -s /run/k3s/containerd/ /run/containerd
[ -x "$(which ufw)" ] && ufw disable && systemctl disable ufw && systemctl stop ufw

# # Lookup own instance information
source /etc/profile.d/zadara-ec2.sh
wait-for-instance-profile
INSTANCE_DATA=$(aws ec2 describe-instances --instance-ids "${K3S_NODE_NAME}" | jq -c --raw-output --arg instance_id "${K3S_NODE_NAME}" '.Reservations[0].Instances[] | select(.InstanceId==$instance_id)')

# # Figure out if new cluster, joining existing cluster, or recovering from object storage
SETUP_STATE="join"
# If control node, and cluster_kapi failed, figure out if node should seed
if [[ "${CLUSTER_ROLE}" == "control" ]] && ! curl -k --head -s -o /dev/null "https://${CLUSTER_KAPI}:6443" > /dev/null 2>&1; then
	CONTROL_PLANE_LAUNCH="$(date +%s)"
	CONTROL_PLANE_SEED=""
	CONTROL_PLANE_SEED_IP=""
	CONTROL_PLANE_ASG=""
	# Identify own ASG
	while [[ -z "${CONTROL_PLANE_ASG}" ]]; do
		CONTROL_PLANE_ASG=$(aws autoscaling describe-auto-scaling-groups | jq -c --raw-output --arg instance_id "${K3S_NODE_NAME}" '.AutoScalingGroups[]|select(.Instances[]?.InstanceId==$instance_id)')
	done
	while [[ -z "${CONTROL_PLANE_SEED_IP}" ]] && ! curl -k --head -s -o /dev/null "https://${CLUSTER_KAPI}:6443" > /dev/null 2>&1; do
		for instance_id in $(echo "${CONTROL_PLANE_ASG}" | jq -c --raw-output '.Instances[].InstanceId'); do
			TEST_INSTANCE_DATA=$(aws ec2 describe-instances --instance-ids "${instance_id}" | jq -c --raw-output --arg instance_id "${instance_id}" '.Reservations[0].Instances[] | select(.InstanceId==$instance_id)')
			TEST_LAUNCH_TIME=$(date -d $(echo "${TEST_INSTANCE_DATA}" | jq -c --raw-output '.LaunchTime') +%s)
			TEST_STATE_CODE=$(echo "${TEST_INSTANCE_DATA}" | jq -c --raw-output '.State.Code')
			[[ ${TEST_STATE_CODE} -ge 32 ]] && continue # Skip this node as it's shutting down
			if [[ ${CONTROL_PLANE_LAUNCH} -gt ${TEST_LAUNCH_TIME} ]]; then
				CONTROL_PLANE_LAUNCH=${TEST_LAUNCH_TIME}
				CONTROL_PLANE_SEED=${instance_id}
				CONTROL_PLANE_SEED_IP=$(echo "${TEST_INSTANCE_DATA}" | jq -c --raw-output '.PrivateIpAddress')
			fi
		done
	done
	[[ "${CONTROL_PLANE_SEED}" == "${K3S_NODE_NAME}" ]] && SETUP_STATE="seed"
fi
# TODO If state is seed, check if there are any matching backups in object storage to recover with

# # Setup k3s
SETUP_ARGS=()
case ${CLUSTER_ROLE} in
	"control")
		SETUP_ARGS+=(
			'server'
			'--embedded-registry'
			'--disable-cloud-controller' # Going to use AWS Cloud Controller Manager instead
			'--disable=local-storage' # Defaulting to EBS-CSI controller, can install local-storage helm chart if needed
			'--disable=servicelb' # Disabling servicelb/klipper to use AWS Loadbalancer controller
			'--flannel-backend=none' # Defaulting to calico chart
			'--disable-network-policy'
			'--tls-san' "${CLUSTER_KAPI}"
		)
		! _gate "controlplane-workload" && SETUP_ARGS+=('--node-taint' 'node-role.kubernetes.io/control-plane=:NoSchedule') # Prevent hosting things on the control plane
		;;
	"worker")
		SETUP_ARGS+=('agent')
		;;
esac
[[ $(lspci -n -d '10de:' | wc -l) -gt 0 ]] && SETUP_ARGS+=('--node-label' "k8s.amazonaws.com/accelerator=nvidia-tesla")
SETUP_ARGS+=(
	'--node-taint' 'ebs.csi.aws.com/agent-not-ready=:NoExecute' # Prevent EBS CSI driver race conditions
	'--kubelet-arg=cloud-provider=external'
	"--kubelet-arg=provider-id=aws:///symphony/${K3S_NODE_NAME}"
)
case ${SETUP_STATE} in
	"recover")
		# TODO Configure S3 restore
		SETUP_ARGS+=(
			'--cluster-init'
			'--cluster-reset'
			'--etcd-s3'
			"--cluster-reset-restore-path=<SNAPSHOT-NAME>"
			"--etcd-s3-bucket=<S3-BUCKET-NAME>"
			"--etcd-s3-access-key=<S3-ACCESS-KEY>"
			"--etcd-s3-secret-key=<S3-SECRET-KEY>"
		)
		;;
	"seed")
		# TODO Configure S3 backup
		SETUP_ARGS+=('--cluster-init')
		;;
	"join")
		SETUP_ARGS+=('--server' "https://${CLUSTER_KAPI}:6443")
		# Wait to ensure CONTROL_PLANE is responsive
		wait-for-endpoint "https://${CLUSTER_KAPI}:6443/cacerts"
		;;
esac
for entry in ${NODE_LABELS[@]}; do
	SETUP_ARGS+=( '--node-label' "${entry}" )
done
for entry in ${NODE_TAINTS[@]}; do
	SETUP_ARGS+=( '--node-taint' "${entry}" )
done
curl -sfL https://get.k3s.io | sh -s - ${SETUP_ARGS[@]}
