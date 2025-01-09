#!/bin/bash
IFS=$'\n'
# Ensure no race condition for configuration file
until [ -e /etc/zadara/k8s.json ]; do sleep 1s ; done
[ ! -d /etc/rancher/k3s ] && mkdir -p /etc/rancher/k3s
[ -e /etc/systemd/system/cleanup-k3s.service ] && systemctl daemon-reload && systemctl enable cleanup-k3s.service
source /etc/profile.d/zadara-ec2.sh

# Read configuration
CLUSTER_NAME="$(jq -c -r '.cluster_name' /etc/zadara/k8s.json)"
CLUSTER_ROLE="$(jq -c -r '.cluster_role' /etc/zadara/k8s.json)"
CLUSTER_VERSION="$(jq -c -r '.cluster_version' /etc/zadara/k8s.json)"
CLUSTER_KAPI="$(jq -c -r '.cluster_kapi' /etc/zadara/k8s.json)"
FEATURE_GATES="$(jq -c -r '.feature_gates' /etc/zadara/k8s.json)"
NODE_LABELS=( $(jq -c -r '.node_labels | to_entries[] | .key + "=" + .value' /etc/zadara/k8s.json | sort) )
NODE_TAINTS=( $(jq -c -r '.node_taints | to_entries[] | .key + "=" + .value' /etc/zadara/k8s.json | sort) )
[ -e /etc/zadara/etcd_backup.json ] && export ETCD_JSON=( $(jq -c -r 'to_entries[]' /etc/zadara/etcd_backup.json) ) || export ETCD_JSON=()
[ ${#ETCD_JSON[@]} -gt 0 ] && export ETCD_RESTORE_PATH=$(jq -c -r '.["cluster-reset-restore-path"]' /etc/zadara/etcd_backup.json) || export ETCD_RESTORE_PATH="null"
export K3S_TOKEN="$(jq -c -r '.cluster_token' /etc/zadara/k8s.json)"
export K3S_NODE_NAME=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export INSTALL_K3S_SKIP_START=true
declare -A role_map=( [control]='server' [worker]='agent' )

[ -n "${CLUSTER_VERSION}" ] && [ "${CLUSTER_VERSION}" != "null" ] && export INSTALL_K3S_VERSION="v${CLUSTER_VERSION}+k3s1"

# Functions
_log() { echo "[$(date +%s)][$0] ${@}" ; }
_gate() { jq -e -c -r --arg element "${1}" 'any(.[];.==$element)' <<< ${FEATURE_GATES} > /dev/null 2>&1; }
cfg-set() {
	target="config.yaml"
	key="${1}"
	val="${2}"
	[ ! -e "/etc/rancher/k3s/${target}" ] && touch "/etc/rancher/k3s/${target}"
	key="${key}" val="${val}" yq e '.[env(key)] = env(val)' -i "/etc/rancher/k3s/${target}"
}
cfg-append() {
	target="config.yaml"
	key="${1}"
	val="${2}"
	[ ! -e "/etc/rancher/k3s/${target}" ] && touch "/etc/rancher/k3s/${target}"
	key="${key}" val="${val}" yq e '.[env(key)] += [env(val)]' -i "/etc/rancher/k3s/${target}"
}

# Logic

# # Setup k3s environment adjustments
ln -s /var/lib/rancher/k3s/agent/etc/containerd/ /etc/containerd
ln -s /run/k3s/containerd/ /run/containerd
# Augment or create /etc/rancher/k3s/registries.yaml configured for the embedded registry
[ -e /etc/rancher/k3s/registries.yaml ] && yq e '.mirrors += {"*":{}}' -i /etc/rancher/k3s/registries.yaml || yq -n -o yaml '.mirrors += {"*":{}}' > /etc/rancher/k3s/registries.yaml

# Install k3s
curl -sfL https://get.k3s.io | sh -s - "${role_map[$CLUSTER_ROLE]}"

# Role-specific settings
case ${CLUSTER_ROLE} in
	"control")
		cfg-append "disable" "local-storage"
                cfg-set "embedded-registry" "true"
                cfg-set "disable-network-policy" "true"
                cfg-set "tls-san" "${CLUSTER_KAPI}"
                cfg-set "flannel-backend" "none"
		! _gate "enable-cloud-controller" && cfg-set 'disable-cloud-controller' "true"
		! _gate "enable-servicelb" && cfg-append 'disable' 'servicelb'
		! _gate "enable-workload-on-controlerplane" && NODE_TAINTS+=('node-role.kubernetes.io/control-plane=:NoSchedule')
		for entry in ${ETCD_JSON[@]}; do
			key=$(echo "${entry}" | jq -c -r '.key')
			val=$(echo "${entry}" | jq -c -r '.value')
			[[ "${key}" == "cluster-reset-restore-path" ]] && continue
			# TODO Validate keys against a whitelist
			cfg-set "etcd-${key}" "${val}"
		done
		;;
	"worker")
		;;
esac
# Common settings
cfg-append "kubelet-arg" "cloud-provider=external"
cfg-append "kubelet-arg" "provider-id=aws:///symphony/${K3S_NODE_NAME}"
[ -e '/etc/rancher/k3s/kubelet.config' ] && cfg-append "kubelet-arg" "config=/etc/rancher/k3s/kubelet.config"
NODE_TAINTS+=('ebs.csi.aws.com/agent-not-ready=:NoExecute')
[[ $(lspci -n -d '10de:' | wc -l) -gt 0 ]] && NODE_LABELS+=('k8s.amazonaws.com/accelerator=nvidia-tesla')

for entry in ${NODE_LABELS[@]}; do
	cfg-append 'node-label' "${entry}"
done
for entry in ${NODE_TAINTS[@]}; do
	cfg-append 'node-taint' "${entry}"
done
# Cluster init/join
SETUP_STATE="join"
SLEEP=1
while [[ "${SETUP_STATE}" == "join" ]] && ! curl -k --head -s -o /dev/null "https://${CLUSTER_KAPI}:6443/cacerts" > /dev/null 2>&1; do
	_log "Waiting for https://${CLUSTER_KAPI}:6443/cacerts to be responsive"
	if [[ "${CLUSTER_ROLE}" == "control" ]]; then
		_log "Checking for seed node"
		# Find my ASG
		while [[ -z "${CONTROL_PLANE_ASG:-}" ]]; do
			CONTROL_PLANE_ASG=$(aws autoscaling describe-auto-scaling-groups | jq -c -r --arg instance_id "${K3S_NODE_NAME}" '.AutoScalingGroups[]|select(.Instances[]?.InstanceId==$instance_id)')
		done
		OLDEST_LAUNCH=$(date +%s)
		OLDEST_NODE=""
		for instance_id in $(echo "${CONTROL_PLANE_ASG}" | jq -c -r '.Instances[].InstanceId'); do
			ASG_PEER=$(aws ec2 describe-instances --instance-ids "${instance_id}" | jq -c -r --arg instance_id "${instance_id}" '.Reservations[0].Instances[] | select(.InstanceId==$instance_id)')
			PEER_LAUNCH=$(date -d $(echo "${ASG_PEER}" | jq -c -r '.LaunchTime') +%s)
			PEER_STATE_CODE=$(echo "${ASG_PEER}" | jq -c -r '.State.Code')
			PEER_IP=$(echo "${ASG_PEER}" | jq -c -r '.PrivateIpAddress')
			[[ ${TEST_STATE_CODE} -ge 32 || -z "${PEER_IP}" || "${PEER_IP}" == "null" ]] && continue
			[ ${OLDEST_LAUNCH} -gt ${PEER_LAUNCH} ] && OLDEST_LAUNCH=${PEER_LAUNCH} && OLDEST_NODE=${instance_id}
		done
		_log "Node '${OLDEST_NODE}' is seed node"
		[ "${OLDEST_NODE}" == "${K3S_NODE_NAME}" ] && SETUP_STATE='seed' && _log "Oh that's me!"
	fi
	[ $SLEEP -lt 10 ] && SLEEP=$((SLEEP + 1))
done
case "${SETUP_STATE}" in
	"join")
		cfg-set "server" "https://${CLUSTER_KAPI}:6443"
		;;
	"seed")
		cfg-set "cluster-init" "true"
		# Recovery phase
		if [[ ( ${#ETCD_JSON[@]} -gt 0 ) && ( -z "${ETCD_RESTORE_PATH}" || "${ETCD_RESTORE_PATH}" == "null" ) ]]; then
			# TODO Add flag to disable restore
			# TODO Search for latest S3 snapshot, set ETCD_RESTORE_PATH
			_log "TODO - Looking for oldest etcd snapshot from remote object storage to restore from"
		fi
		[ -n "${ETCD_RESTORE_PATH}" ] && [ "${ETCD_RESTORE_PATH}" != "null" ] && cfg-set "cluster-reset" "true" && cfg-set "cluster-reset-restore-path" "${ETCD_RESTORE_PATH}"
		;;
esac

# Start k3s
_log "Starting k3s"
[ "${CLUSTER_ROLE}" == "control" ] && systemctl start k3s
[ "${CLUSTER_ROLE}" == "worker" ] && systemctl start k3s-agent
