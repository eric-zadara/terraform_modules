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
export K3S_TOKEN="$(jq -c -r '.cluster_token' /etc/zadara/k8s.json)"
export K3S_NODE_NAME=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export INSTALL_K3S_SKIP_START=true

[ -n "${CLUSTER_VERSION}" ] && [ "${CLUSTER_VERSION}" != "null" ] && export INSTALL_K3S_VERSION="v${CLUSTER_VERSION}+k3s1"

# Functions
_log() { echo "[$(date +%s)][$0]${@}" ; }
_gate() { jq -e -c -r --arg element "${1}" 'any(.[];.==$element)' <<< ${FEATURE_GATES} > /dev/null 2>&1; }
wait-for-endpoint() {
	# $1 should be http[s]://<target>:port
	SLEEP=${SLEEP:-1}
	until curl -k --head -s -o /dev/null "${1}" > /dev/null 2>&1; do
		sleep ${SLEEP}s
		[ $SLEEP -lt 10 ] && SLEEP=$((SLEEP + 1))
		[ $SLEEP -ge 10 ] && _log "[wait-for-endpoint] Waiting ${SLEEP}s for ${1}"
	done
}
set-cfg() {
	target="config.yaml"
	key="${1}"
	val="${2}"
	[ ! -e "/etc/rancher/k3s/${target}" ] && touch "/etc/rancher/k3s/${target}"
	key="${key}" val="${val}" yq -i -o yaml '.[env(key)] = env(val)' "/etc/rancher/k3s/${target}"
}

# # Setup k3s adjustments
ln -s /var/lib/rancher/k3s/agent/etc/containerd/ /etc/containerd
ln -s /run/k3s/containerd/ /run/containerd

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
		CONTROL_PLANE_ASG=$(aws autoscaling describe-auto-scaling-groups | jq -c -r --arg instance_id "${K3S_NODE_NAME}" '.AutoScalingGroups[]|select(.Instances[]?.InstanceId==$instance_id)')
	done
	while [[ -z "${CONTROL_PLANE_SEED_IP}" ]] && ! curl -k --head -s -o /dev/null "https://${CLUSTER_KAPI}:6443" > /dev/null 2>&1; do
		for instance_id in $(echo "${CONTROL_PLANE_ASG}" | jq -c -r '.Instances[].InstanceId'); do
			TEST_INSTANCE_DATA=$(aws ec2 describe-instances --instance-ids "${instance_id}" | jq -c -r --arg instance_id "${instance_id}" '.Reservations[0].Instances[] | select(.InstanceId==$instance_id)')
			TEST_LAUNCH_TIME=$(date -d $(echo "${TEST_INSTANCE_DATA}" | jq -c -r '.LaunchTime') +%s)
			TEST_STATE_CODE=$(echo "${TEST_INSTANCE_DATA}" | jq -c -r '.State.Code')
			[[ ${TEST_STATE_CODE} -ge 32 ]] && continue # Skip this node as its shutting down
			if [[ ${CONTROL_PLANE_LAUNCH} -gt ${TEST_LAUNCH_TIME} ]]; then
				CONTROL_PLANE_LAUNCH=${TEST_LAUNCH_TIME}
				CONTROL_PLANE_SEED=${instance_id}
				CONTROL_PLANE_SEED_IP=$(echo "${TEST_INSTANCE_DATA}" | jq -c -r '.PrivateIpAddress')
			fi
		done
	done
	[[ "${CONTROL_PLANE_SEED}" == "${K3S_NODE_NAME}" ]] && SETUP_STATE="seed"
fi
[ -e /etc/zadara/etcd_backup.json ] && export ETCD_JSON=( $(jq -c -r 'to_entries[]' /etc/zadara/etcd_backup.json) ) || export ETCD_JSON=()
[ ${#ETCD_JSON[@]} -gt 0 ] && export ETCD_RESTORE_PATH=$(jq -c -r '.["cluster-reset-restore-path"]' /etc/zadara/etcd_backup.json) || export ETCD_RESTORE_PATH="null"
if [[ "${SETUP_STATE}" == "seed" && ${#ETCD_JSON[@]} -gt 0 && ( -z "${ETCD_RESTORE_PATH}" || "${ETCD_RESTORE_PATH}" != "null" ) ]]; then
	_log "State is seed, etcd configuration has been specified, but no restore-path has been defined."
	_log "TODO - Add flag to disable auto-restore" # TODO
	_log "TODO - Validate etcd object-store is functional, see if any backups exist, select latest backup to restore with and set ETCD_RESTORE_PATH to it" # TODO
fi

# # Setup k3s
SETUP_ARGS=()
case ${CLUSTER_ROLE} in
	"control")
		set-cfg "embedded-registry" "true"
		set-cfg "disable-network-policy" "true"
		set-cfg "tls-san" "${CLUSTER_KAPI}"
		set-cfg "flannel-backend" "none"
		SETUP_ARGS+=(
			'server'
			'--disable=local-storage' # Defaulting to EBS-CSI controller, can install local-storage helm chart if needed
		)
		! _gate "enable-cloud-controller" && set-cfg 'disable-cloud-controller' "true" # Going to use AWS Cloud Controller Manager instead
		! _gate "enable-servicelb" && SETUP_ARGS+=('--disable=servicelb') # Disabling servicelb/klipper to use AWS Loadbalancer controller
		! _gate "controlplane-workload" && NODE_TAINTS+=('node-role.kubernetes.io/control-plane=:NoSchedule') # Prevent hosting things on the control plane
		;;
	"worker")
		SETUP_ARGS+=('agent')
		;;
esac
[[ $(lspci -n -d '10de:' | wc -l) -gt 0 ]] && NODE_LABELS+=('k8s.amazonaws.com/accelerator=nvidia-tesla')
NODE_TAINTS+=('ebs.csi.aws.com/agent-not-ready=:NoExecute')
SETUP_ARGS+=(
	'--kubelet-arg=cloud-provider=external'
	"--kubelet-arg=provider-id=aws:///symphony/${K3S_NODE_NAME}"
)
[ -e '/etc/rancher/k3s/kubelet.config' ] && SETUP_ARGS+=( "--kubelet-arg=config=/etc/rancher/k3s/kubelet.config" )
case ${SETUP_STATE} in
	"seed")
		set-cfg "cluster-init" "true"
		;;
	"join")
		set-cfg "server" "https://${CLUSTER_KAPI}:6443"
		# Wait to ensure CONTROL_PLANE is responsive
		wait-for-endpoint "https://${CLUSTER_KAPI}:6443/cacerts"
		;;
esac
# Restore is seed with extra steps
if [[ "${CLUSTER_ROLE}" == "control" ]]; then
	[ "${SETUP_STATE}" == "seed" ] && [ -n "${ETCD_RESTORE_PATH}" ] && [ "${ETCD_RESTORE_PATH}" != "null" ] && SETUP_ARGS+=( '--cluster-reset' "--cluster-reset-restore-path=${ETCD_RESTORE_PATH}")
	for entry in ${ETCD_JSON[@]}; do
		key=$(echo "${entry}" | jq -c -r '.key')
		val=$(echo "${entry}" | jq -c -r '.value')
		[[ "${key}" == "cluster-reset-restore-path" ]] && continue
		# TODO Validate keys against a whitelist
		set-cfg "etcd-${key}" "${val}"
	done
fi
for entry in ${NODE_LABELS[@]}; do
	SETUP_ARGS+=( '--node-label' "${entry}" )
done
for entry in ${NODE_TAINTS[@]}; do
	SETUP_ARGS+=( '--node-taint' "${entry}" )
done
# Augment or create /etc/rancher/k3s/registries.yaml configured for the embedded registry
[ -e /etc/rancher/k3s/registries.yaml ] && yq -i -o yaml '.mirrors += {"*":{}}' /etc/rancher/k3s/registries.yaml || yq -n -o yaml '.mirrors += {"*":{}}' > /etc/rancher/k3s/registries.yaml
curl -sfL https://get.k3s.io | sh -s - ${SETUP_ARGS[@]}
# Recovery phase
# Start k3s
[ "${CLUSTER_ROLE}" == "control" ] && systemctl start k3s
[ "${CLUSTER_ROLE}" == "worker" ] && systemctl start k3s-agent
