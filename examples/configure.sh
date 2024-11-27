#!/bin/bash
IFS=$'\n'
shopt -s extglob
## Configuration
TFVARS_FILE="config.auto.tfvars"

## Functions
function _usage {
	echo "Usage: $0 <folder>"
}

function _save {
	PATTERN="${1}"
	LINE="${2}"
	sed -i "/^${PATTERN}$/a${LINE}" "${TFVARS_FILE}"
}

function wizard {
	cd "${1}"
	FILES=( $(ls -1 *.tf | sort) )
	for FILENAME in ${FILES[@]}; do
		VARS=( $(awk '/^variable/{ print $2 }' ${FILENAME} | tr -d '"') )
		if [ ${#VARS[@]} -gt 0 ]; then
			echo "== ${FILENAME}"
			grep -s -qxF "# ${FILENAME}" "${TFVARS_FILE}" || echo "# ${FILENAME}" >> "${TFVARS_FILE}"
		fi
		for VAR in ${VARS[@]}; do
			[ -e "${TFVARS_FILE}" ] && grep -qE "^$VAR +=" "${TFVARS_FILE}" && continue
			CFG=$(awk -v VAR="${VAR}" '$0 ~ "variable \""VAR"\"",/^}/' "${FILENAME}")
			DEFAULT=$(echo "$CFG" | awk -F'["]' '/default /{print $2}')
			[ -n "${DEFAULT}" ] && continue
			TYPE=$(echo "$CFG" | awk -F'[ ]' '/type /{print $NF}')
			DESCRIPTION=$(echo "$CFG" | awk -F'["]' '/description /{print $2}')
			SENSITIVE=$(echo "$CFG" | awk -F'[ ]' '/sensitive /{print $NF}')
			echo -e "# ${VAR}(${TYPE}) => ${DESCRIPTION}"
			[ "${SENSITIVE}" == "true" ] && read -s -p "${VAR}> " value && echo
			[ "${SENSITIVE}" != "true" ] && read -p "${VAR}> " value
			case "${TYPE}" in
				string) _save "# ${FILENAME}" "${VAR} = \"${value}\"" ;;
				bool) _save "# ${FILENAME}" "${VAR} = ${value}" ;;
			esac
		done
		[ ${#VARS[@]} -gt 0 ] && echo ""
	done
}

## Logic
[ ${#} -ne 1 ] && _usage && exit 1
[ ${#} -eq 1 ] && [ ! -d "${1}" ] && echo "Error: '${1}' not found" && _usage && exit 1
wizard "${1}"
