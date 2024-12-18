#!/bin/bash
IFS=$'\n'
until [ -e /etc/zadara/k8s.json ]; do sleep 1s ; done
_log() { echo "[$(date +%s)][$0]${@}" ; }
[ ! -e /etc/zadara/k8s_helm.json ] && _log "[exit] No helm manifest found at /etc/zadara/k8s_helm.json." && exit

CLUSTER_NAME="$(jq -c -r '.cluster_name' /etc/zadara/k8s.json)"
CLUSTER_ROLE="$(jq -c -r '.cluster_role' /etc/zadara/k8s.json)"
CLUSTER_KAPI="$(jq -c -r '.cluster_kapi' /etc/zadara/k8s.json)"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
LABEL_MUTEX="dev.zadara/setup-helm"

[ "${CLUSTER_ROLE}" != "control" ] && _log "[exit] Role(${CLUSTER_ROLE}) is not 'control'." && exit
for x in '/etc/profile.d/k3s-kubeconfig.sh' '/etc/profile.d/zadara-ec2.sh'; do
	until [ -e ${x} ]; do sleep 1s ; done
	source ${x}
done
export HELM_CACHE_HOME=/root/.cache/helm
export HELM_CONFIG_HOME=/root/.config/helm
export HELM_DATA_HOME=/root/.local/share/helm

# Functions
wait-for-endpoint() {
	# $1 should be http[s]://<target>:port
	SLEEP=${SLEEP:-1}
	until curl -k --head -s -o /dev/null "${1}" > /dev/null 2>&1; do
		sleep ${SLEEP}s
		[ $SLEEP -lt 10 ] && SLEEP=$((SLEEP + 1))
		[ $SLEEP -ge 10 ] && _log "[wait-for-endpoint] Waiting ${SLEEP}s for ${1}"
	done
}

# Wait for loadbalancer kapi to be responsive
wait-for-endpoint "https://${CLUSTER_KAPI}:6443/cacerts"
# Wait for local kapi to be responsive
wait-for-endpoint "https://localhost:6443/cacerts"
until [ -n "$(which kubectl)" ]; do sleep 1s ; done
[ -z "$(which helm)" ] && curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

until [ -e ${KUBECONFIG} ]; do sleep 1s ; done
[ $(kubectl get nodes -l ${LABEL_MUTEX} -o name --sort-by='.metadata.creationTimestamp' 2> /dev/null | wc -l) -gt 0 ] && kubectl label nodes ${INSTANCE_ID} ${LABEL_MUTEX}- && _log "Mutex ${LABEL_MUTEX} found, exiting." && exit
kubectl label nodes ${INSTANCE_ID} ${LABEL_MUTEX}=$(date +%s)
for addon in $(jq -c -r 'to_entries[] | {"repository_name": .value.repository_name, "repository_url": .value.repository_url}' /etc/zadara/k8s_helm.json | sort -u); do
	repository_name=$(echo "${addon}" | jq -c -r '.repository_name')
	repository_url=$(echo "${addon}" | jq -c -r '.repository_url')
	_log "helm repo add '${repository_name}' '${repository_url}'"
	helm repo add "${repository_name}" "${repository_url}"
done
helm repo update
for addon in $(jq -c -r 'to_entries | sort_by(.value.order, .key)[]' /etc/zadara/k8s_helm.json); do
	id=$(echo "${addon}" | jq -c -r '.key')
	repository_name=$(echo "${addon}" | jq -c -r '.value.repository_name')
	chart=$(echo "${addon}" | jq -c -r '.value.chart')
	should_wait=$(echo "${addon}" | jq -c -r '.value.wait')
	version=$(echo "${addon}" | jq -c -r '.value.version')
	namespace=$(echo "${addon}" | jq -c -r '.value.namespace')
	config=$(echo "${addon}" | jq -c -r '.value.config')
	existing=$(helm list -A -o json | jq -c -r --arg app_name "${id}" '.[]|select(.name==$app_name)')
	existing_config=$(helm get values "${id}" -n "${namespace}" -o json 2>/dev/null | jq -c -r '.')
	if [[ "$(echo "${existing}" | jq -c -r '.chart')" != "${chart}-${version}" || "$(jq -c -r --slurpfile a <(echo "${config}") --slurpfile b <(echo "${existing_config}") -n '$a == $b')" == "false" ]]; then
		HELM_ARGS=(
			'upgrade'
			'--install' "${id}"
			"${repository_name}/${chart}"
			'--version' "${version}"
			'--namespace' "${namespace}"
			'--create-namespace'
			'--kube-apiserver' "https://${CLUSTER_KAPI}:6443"
		)
		[[ "${should_wait:-}" == "true" ]] && HELM_ARGS+=("--wait")
		_log "[executing] helm ${HELM_ARGS[@]}"
		if [[ "${config}" != "null" ]]; then
			false
			until [ $? -eq 0 ]; do helm ${HELM_ARGS[@]} -f <(echo "${config}") ; done
		else
			false
			until [ $? -eq 0 ]; do helm ${HELM_ARGS[@]} ; done
		fi
	fi
done
kubectl label nodes ${INSTANCE_ID} ${LABEL_MUTEX}-
