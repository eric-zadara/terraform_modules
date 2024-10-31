#!/bin/bash
IFS=$'\n'
until [ -e /etc/zadara/k8s.json ]; do sleep 1s ; done
_log() { echo "[$(date +%s)][$0]${@}" ; }
CLUSTER_NAME="$(jq -c --raw-output '.cluster_name' /etc/zadara/k8s.json)"
CLUSTER_ROLE="$(jq -c --raw-output '.cluster_role' /etc/zadara/k8s.json)"
CLUSTER_KAPI="$(jq -c --raw-output '.cluster_kapi' /etc/zadara/k8s.json)"
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

[ ! -e /etc/zadara/k8s_helm.json ] && _log "[exit] No helm manifest found." && exit

for addon in $(jq -c --raw-output 'to_entries[] | {"repository_name": .value.repository_name, "repository_url": .value.repository_url}' /etc/zadara/k8s_helm.json | sort -u); do
	repository_name=$(echo "${addon}" | jq -c --raw-output '.repository_name')
	repository_url=$(echo "${addon}" | jq -c --raw-output '.repository_url')
	helm repo add "${repository_name}" "${repository_url}"
done
helm repo update
for addon in $(jq -c --raw-output 'to_entries | sort_by(.value.sort, .key)[]' /etc/zadara/k8s_helm.json); do
	id=$(echo "${addon}" | jq -c --raw-output '.key')
	repository_name=$(echo "${addon}" | jq -c --raw-output '.value.repository_name')
	chart=$(echo "${addon}" | jq -c --raw-output '.value.chart')
	should_wait=$(echo "${addon}" | jq -c --raw-output '.value.wait')
	version=$(echo "${addon}" | jq -c --raw-output '.value.version')
	namespace=$(echo "${addon}" | jq -c --raw-output '.value.namespace')
	config=$(echo "${addon}" | jq -c --raw-output '.value.config')
	existing=$(helm list -A -o json | jq -c --raw-output --arg app_name "${id}" '.[]|select(.name==$app_name)')
	if [[ -z "${existing}" || "$(echo "${existing}" | jq -c --raw-output '.chart')" != "${chart}-${version}" ]]; then
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
		[[ "${config}" != "null" ]] && helm ${HELM_ARGS[@]} -f <(echo "${config}") || helm ${HELM_ARGS[@]}
	fi
done
