#!/bin/sh
#
# K2HR3 Container Registration Sidecar
#
# Copyright 2019 Yahoo Japan Corporation.
#
# K2HR3 is K2hdkc based Resource and Roles and policy Rules, gathers
# common management information for the cloud.
# K2HR3 can dynamically manage information as "who", "what", "operate".
# These are stored as roles, resources, policies in K2hdkc, and the
# client system can dynamically read and modify these information.
#
# For the full copyright and license information, please view
# the license file that was distributed with this source code.
#
# AUTHOR:   Takeshi Nakatani
# CREATE:   Thu Jul 4 2019
# REVISION:
#

########################################################################
# k2hr3-k8s-init.sh
########################################################################
# This shell script is for registration/deletion the container created in
# kubernetes to/from the K2HR3 role member.
# This file is expected to be launched as a Sidecar container.
########################################################################

#
# Environments
#
# This script expects the following environment variables to be set.
# These values are used as elements of CUK data when registering to K2HR3 Role members.
#
#	K2HR3_NODE_NAME				node name on this container's node(spec.nodeName)
#	K2HR3_NODE_IP				node host ip address on this container's node(status.hostIP)
#	K2HR3_POD_NAME				pod name containing this container(metadata.name)
#	K2HR3_POD_NAMESPACE			pod namespace for this container(metadata.namespace)
#	K2HR3_POD_SERVICE_ACCOUNT	pod service account for this container(spec.serviceAccountName)
#	K2HR3_POD_ID				pod id containing this container(metadata.uid)
#	K2HR3_POD_IP				pod ip address containing this container(status.podIP)
#
# The following values are also added to CUK data.
#
#	K2HR3_CONTAINER_ID			This value is the <docker id> that this script reads from /proc/<pid>/cgroups.
#								(kubernetes uses this <docker id> as the <container id>.)
#
K2HR3_CONTAINER_ID=""

#
# Files on volume disk
#
# This script outputs the following files under the volume disk.
# These file contents can be used when accessing K2HR3.
# It also contains a script for removing containers from K2HR3 role members.
#
#	K2HR3_FILE_ROLE				yrn full path to the role
#	K2HR3_FILE_CUK				cuk value for url argument to K2HR3 API(PUT/GET/DELETE/etc)
#	K2HR3_FILE_CUKENC			urlencoded cuk value
#	K2HR3_FILE_APIARG			packed cuk argument("extra=...&cuk=value") to K2HR3 API(PUT/GET/DELETE/etc)
#	K2HR3_FILE_DEINIT_SH		Shell script to delete from K2HR3 role member.
#
K2HR3_FILE_ROLE="k2hr3-role"
K2HR3_FILE_CUK="k2hr3-cuk"
K2HR3_FILE_CUKENC="k2hr3-cukencode"
K2HR3_FILE_APIARG="k2hr3-apiarg"
K2HR3_FILE_DEINIT_SH="k2hr3-k8s-deinit.sh"

#
# Options
#
func_usage()
{
	echo ""
	echo "Usage: $1 [ -reg | -del ] [options...]"
	echo "    -reg | -del                   Specifies the behavior(registration or deletion) of this script."
	echo "    -rtoken <K2HR3 Role token>    The Role token for registration(not be omitted for registration)."
	echo "    -role <K2HR3 Role YRN path>   The YRN full path of the Role to be registered as a member(not be omitted)."
	echo "    -host <K2HR3 API server>      The hostname or IP address of the K2HR3 API server(not be omitted)."
	echo "    -port <K2HR3 API port>        The port number of the K2HR3 API server(443 or 80 is set by default)."
	echo "    -schema <K2HR3 API schema>    The schema(http or https) of the K2HR3 API(\"https\" is set by default)."
	echo "    -uri <K2HR3 API uri path>     The Role member registration/deletion URI path(\"/v1/role\" is set by default)."
	echo "    -volume <mount path>          The path where volume disk was mounted(\"/k2hr3-volume\" is set by default)."
	echo ""
	echo "Environments"
	echo "    K2HR3_NODE_NAME               node name on this container's node(spec.nodeName)"
	echo "    K2HR3_NODE_IP                 node host ip address on this container's node(status.hostIP)"
	echo "    K2HR3_POD_NAME                pod name containing this container(metadata.name)"
	echo "    K2HR3_POD_NAMESPACE           pod namespace for this container(metadata.namespace)"
	echo "    K2HR3_POD_SERVICE_ACCOUNT     pod service account for this container(spec.serviceAccountName)"
	echo "    K2HR3_POD_ID                  pod id containing this container(metadata.uid)"
	echo "    K2HR3_POD_IP                  pod ip address containing this container(status.podIP)"
	echo ""
}

#
# Common
#
PRGNAME=$(basename "$0")
#SCRIPTDIR=$(dirname "$0")
#SRCTOP=$(cd "${SCRIPTDIR}" || exit 1; pwd)

#
# Parse options
#
K2HR3_BEHAVIOR=
K2HR3_ROLE_TOKEN=""
K2HR3_ROLE_YRN=""
K2HR3_API_HOST=""
K2HR3_API_PORT=
K2HR3_API_SCHEMA=""
K2HR3_API_URI=""
K2HR3_VOLUME_PATH=""
while [ $# -ne 0 ]; do
	if [ -z "$1" ]; then
		break

	elif echo "$1" | grep -q -i -e "^-h$" -e "^--help$"; then
		func_usage "${PRGNAME}"
		exit 0

	elif echo "$1" | grep -q -i "^-reg$"; then
		if [ -n "${K2HR3_BEHAVIOR}" ]; then
			echo "[ERROR] ${PRGNAME} : already set behavior(registration or deletion)." 1>&2
			exit 1
		fi
		K2HR3_BEHAVIOR="reg"

	elif echo "$1" | grep -q -i "^-del$"; then
		if [ -n "${K2HR3_BEHAVIOR}" ]; then
			echo "[ERROR] ${PRGNAME} : already set behavior(registration or deletion)." 1>&2
			exit 1
		fi
		K2HR3_BEHAVIOR="del"

	elif echo "$1" | grep -q -i "^-rtoken$"; then
		if [ -n "${K2HR3_ROLE_TOKEN}" ]; then
			echo "[ERROR] ${PRGNAME} : already set role token(${K2HR3_ROLE_TOKEN})." 1>&2
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			echo "[ERROR] ${PRGNAME} : -rtoken option is specified without parameter." 1>&2
			exit 1
		fi
		K2HR3_ROLE_TOKEN="$1"

	elif echo "$1" | grep -q -i "^-role$"; then
		if [ -n "${K2HR3_ROLE_YRN}" ]; then
			echo "[ERROR] ${PRGNAME} : already set role yrn full path(${K2HR3_ROLE_YRN})." 1>&2
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			echo "[ERROR] ${PRGNAME} : -role option is specified without parameter." 1>&2
			exit 1
		fi
		K2HR3_ROLE_YRN="$1"

	elif echo "$1" | grep -q -i "^-host$"; then
		if [ -n "${K2HR3_API_HOST}" ]; then
			echo "[ERROR] ${PRGNAME} : already set K2HR3 API server(${K2HR3_API_HOST})." 1>&2
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			echo "[ERROR] ${PRGNAME} : -host option is specified without parameter." 1>&2
			exit 1
		fi
		K2HR3_API_HOST="$1"

	elif echo "$1" | grep -q -i "^-port$"; then
		if [ -n "${K2HR3_API_PORT}" ]; then
			echo "[ERROR] ${PRGNAME} : already set K2HR3 API port(${K2HR3_API_PORT})." 1>&2
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			echo "[ERROR] ${PRGNAME} : -port option is specified without parameter." 1>&2
			exit 1
		fi
		# check number
		if echo "$1" | grep -q "[^0-9]"; then
			echo "[ERROR] ${PRGNAME} : -port option parameter is not number($1)." 1>&2
			exit 1
		fi
		K2HR3_API_PORT="$1"

	elif echo "$1" | grep -q -i "^-schema$"; then
		if [ -n "${K2HR3_API_SCHEMA}" ]; then
			echo "[ERROR] ${PRGNAME} : already set K2HR3 API schema(${K2HR3_API_SCHEMA})." 1>&2
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			echo "[ERROR] ${PRGNAME} : -schema option is specified without parameter." 1>&2
			exit 1
		fi
		if echo "$1" | grep -q -i "^http$"; then
			K2HR3_API_SCHEMA="http"
		elif echo "$1" | grep -q -i "^https$"; then
			K2HR3_API_SCHEMA="https"
		else
			echo "[ERROR] ${PRGNAME} : -schema option parameter is wrong value($1)." 1>&2
			exit 1
		fi

	elif echo "$1" | grep -q -i "^-uri$"; then
		if [ -n "${K2HR3_API_URI}" ]; then
			echo "[ERROR] ${PRGNAME} : already set registration/deletion URI path(${K2HR3_API_URI})." 1>&2
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			echo "[ERROR] ${PRGNAME} : -uri option is specified without parameter." 1>&2
			exit 1
		fi
		K2HR3_API_URI="$1"

	elif echo "$1" | grep -q -i "^-volume$"; then
		if [ -n "${K2HR3_VOLUME_PATH}" ]; then
			echo "[ERROR] ${PRGNAME} : already set volume disk path(${K2HR3_VOLUME_PATH})." 1>&2
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			echo "[ERROR] ${PRGNAME} : -volume option is specified without parameter." 1>&2
			exit 1
		fi
		K2HR3_VOLUME_PATH="$1"

	else
		echo "[ERROR] ${PRGNAME} : unknown option($1) is specified." 1>&2
		exit 1
	fi
	shift
done

#
# Check options
#
if [ -z "${K2HR3_BEHAVIOR}" ]; then
	echo "[ERROR] ${PRGNAME} : Must specify the behavior option of this script: registration(-reg) or deletion(-del)." 1>&2
	exit 1
fi
if [ -z "${K2HR3_ROLE_TOKEN}" ]; then
	if [ "${K2HR3_BEHAVIOR}" = "reg" ]; then
		echo "[ERROR] ${PRGNAME} : -rtoken option is not specified." 1>&2
		exit 1
	fi
fi
if [ -z "${K2HR3_ROLE_YRN}" ]; then
	echo "[ERROR] ${PRGNAME} : -role option is not specified." 1>&2
	exit 1
fi
if [ -z "${K2HR3_API_HOST}" ]; then
	echo "[ERROR] ${PRGNAME} : -host option is not specified." 1>&2
	exit 1
fi
if [ -z "${K2HR3_API_PORT}" ] && [ -z "${K2HR3_API_SCHEMA}" ]; then
	K2HR3_API_PORT=443
	K2HR3_API_SCHEMA="https"
elif [ -n "${K2HR3_API_PORT}" ] && [ -z "${K2HR3_API_SCHEMA}" ]; then
	if [ "${K2HR3_API_PORT}" -eq 80 ]; then
		K2HR3_API_SCHEMA="http"
	else
		K2HR3_API_SCHEMA="https"
	fi
elif [ -z "${K2HR3_API_PORT}" ] && [ -n "${K2HR3_API_SCHEMA}" ]; then
	if [ "${K2HR3_API_SCHEMA}" = "http" ]; then
		K2HR3_API_PORT=80
	else
		K2HR3_API_PORT=443
	fi
fi
if [ -z "${K2HR3_API_URI}" ]; then
	K2HR3_API_URI="/v1/role"
fi
if [ -z "${K2HR3_VOLUME_PATH}" ]; then
	K2HR3_VOLUME_PATH="/k2hr3-volume"
fi
if [ "${K2HR3_BEHAVIOR}" = "reg" ]; then
	if [ ! -d "${K2HR3_VOLUME_PATH}" ]; then
		echo "[ERROR] ${PRGNAME} : volume disk(${K2HR3_VOLUME_PATH}) is not found or not directory." 1>&2
		exit 1
	fi
fi

#
# Processing
#
if [ "${K2HR3_BEHAVIOR}" = "reg" ]; then
	#
	# Registration
	#

	#
	# Make container id with checking pod id
	#
	# shellcheck disable=SC2010
	if ! local_proc_ids=$(ls -1 /proc/ | grep -E "[0-9]+" 2>/dev/null); then
		echo "[ERROR] ${PRGNAME} : Could not find any /proc/<process id> directory." 1>&2
		exit 1
	fi

	local_uid_containerid=""
	for local_procid in ${local_proc_ids}; do
		if [ ! -f "/proc/${local_procid}/cgroup" ]; then
			continue
		fi
		if ! local_all_line=$(cat "/proc/${local_procid}/cgroup"); then
			continue
		fi
		for local_line in ${local_all_line}; do
			if ! local_uid_containerid=$(echo "${local_line}" | sed -e 's#.*pod##g' -e 's#\.slice##g' -e 's#\.scope##g' -e 's#docker-##g' 2>/dev/null); then
				continue
			fi
			if [ -n "${local_uid_containerid}" ]; then
				break
			fi
		done
		if [ -n "${local_uid_containerid}" ]; then
			break
		fi
	done

	if [ -n "${local_uid_containerid}" ]; then
		K2HR3_TMP_POD_ID=$(echo "${local_uid_containerid}" | sed -e 's#/# #g' 2>/dev/null | awk '{print $1}' 2>/dev/null)
		K2HR3_CONTAINER_ID=$(echo "${local_uid_containerid}" | sed -e 's#/# #g' 2>/dev/null | awk '{print $2}' 2>/dev/null)

		if [ -z "${K2HR3_POD_ID}" ]; then
			K2HR3_POD_ID="${K2HR3_TMP_POD_ID}"
		else
			if [ "${K2HR3_POD_ID}" != "${K2HR3_TMP_POD_ID}" ]; then
				echo "[WARNING] ${PRGNAME} : Specified pod id(${K2HR3_POD_ID}) is not correct, so that use current pod id(${K2HR3_TMP_POD_ID}) instead of it." 1>&2
				K2HR3_POD_ID="${K2HR3_TMP_POD_ID}"
			fi
		fi
	fi
	if [ -z "${K2HR3_CONTAINER_ID}" ]; then
		echo "[ERROR] ${PRGNAME} : Could not get container id." 1>&2
		exit 1
	fi

	#
	# Check all parameters in environment
	#
	if [ -z "${K2HR3_NODE_NAME}" ]; then
		echo "[ERROR] ${PRGNAME} : Environment K2HR3_NODE_NAME is not specified." 1>&2
		exit 1
	fi
	if [ -z "${K2HR3_NODE_IP}" ]; then
		echo "[ERROR] ${PRGNAME} : Environment K2HR3_NODE_IP is not specified." 1>&2
		exit 1
	fi
	if [ -z "${K2HR3_POD_NAME}" ]; then
		echo "[ERROR] ${PRGNAME} : Environment K2HR3_POD_NAME is not specified." 1>&2
		exit 1
	fi
	if [ -z "${K2HR3_POD_NAMESPACE}" ]; then
		echo "[ERROR] ${PRGNAME} : Environment K2HR3_POD_NAMESPACE is not specified." 1>&2
		exit 1
	fi
	if [ -z "${K2HR3_POD_SERVICE_ACCOUNT}" ]; then
		echo "[ERROR] ${PRGNAME} : Environment K2HR3_POD_SERVICE_ACCOUNT is not specified." 1>&2
		exit 1
	fi
	if [ -z "${K2HR3_POD_ID}" ]; then
		echo "[ERROR] ${PRGNAME} : Environment K2HR3_POD_ID is not specified." 1>&2
		exit 1
	fi
	if [ -z "${K2HR3_POD_IP}" ]; then
		echo "[ERROR] ${PRGNAME} : Environment K2HR3_POD_IP is not specified." 1>&2
		exit 1
	fi

	#
	# Make CUK parameter
	#
	# The CUK parameter is a base64 url encoded value from following JSON object string(sorted keys by a-z).
	#	{
	#		"k8s_namespace":		${K2HR3_POD_NAMESPACE}
	#		"k8s_service_account":	${K2HR3_POD_SERVICE_ACCOUNT}
	#		"k8s_node_name":		${K2HR3_NODE_NAME},
	#		"k8s_node_ip":			${K2HR3_NODE_IP},
	#		"k8s_pod_name":			${K2HR3_POD_NAME},
	#		"k8s_pod_id":			${K2HR3_POD_ID}
	#		"k8s_pod_ip":			${K2HR3_POD_IP}
	#		"k8s_container_id":		${K2HR3_CONTAINER_ID}
	#		"k8s_k2hr3_rand":		"random 32 byte value formatted hex string"
	#	}
	#
	# Base64 URL encoding converts the following characters.
	#	'+'				to '-'
	#	'/'				to '_'
	#	'='(end word)	to '%3d'
	#
	if ! K2HR3_REG_RAND=$(od -vAn -tx8 -N16 < /dev/urandom 2>/dev/null | tr -d '[:blank:]' 2>/dev/null); then
		echo "[ERROR] ${PRGNAME} : Could not make 64 bytes random value for CUK value." 1>&2
		exit 1
	fi

	local_cuk_string="{
\"k8s_container_id\":\"${K2HR3_CONTAINER_ID}\",
\"k8s_k2hr3_rand\":\"${K2HR3_REG_RAND}\",
\"k8s_namespace\":\"${K2HR3_POD_NAMESPACE}\",
\"k8s_node_ip\":\"${K2HR3_NODE_IP}\",
\"k8s_node_name\":\"${K2HR3_NODE_NAME}\",
\"k8s_pod_id\":\"${K2HR3_POD_ID}\",
\"k8s_pod_ip\":\"${K2HR3_POD_IP}\",
\"k8s_pod_name\":\"${K2HR3_POD_NAME}\",
\"k8s_service_account\":\"${K2HR3_POD_SERVICE_ACCOUNT}\"
}"

	if ! local_cuk_base64=$(printf '%s' "${local_cuk_string}" | sed -e 's/ //g' | base64 | tr -d '\n'); then
		echo "[ERROR] ${PRGNAME} : Could not make base64 string for CUK value." 1>&2
		exit 1
	fi
	if ! local_cuk_base64_urlenc=$(printf '%s' "${local_cuk_base64}" | sed -e 's/+/-/g' -e 's#/#_#g' -e 's/=/%3d/g'); then
		echo "[ERROR] ${PRGNAME} : Could not make base64 url encode string for CUK value." 1>&2
		exit 1
	fi

	#
	# Make EXTRA parameter
	#
	# Currently, the value of "extra" is "k8s-auto-v1" only.
	#
	local_extra_string="k8s-auto-v1"

	#
	# Call K2HR3 REST API
	#
	# Example: 
	#	curl -s -S -X PUT -H "x-auth-token: R=<ROLE TOKEN>" "http(s)://<k2hr3 api host>:<port>/<uri>/<role yrn>?extra=k8s-auto-v1&cuk=<cuk parameter>"
	#
	if ! curl -s -S -X PUT -H "x-auth-token: R=${K2HR3_ROLE_TOKEN}" "${K2HR3_API_SCHEMA}://${K2HR3_API_HOST}:${K2HR3_API_PORT}${K2HR3_API_URI}/${K2HR3_ROLE_YRN}?extra=${local_extra_string}&cuk=${local_cuk_base64_urlenc}"; then
		echo "[ERROR] ${PRGNAME} : Failed registration to role member." 1>&2
		exit 1
	fi

	#
	# Make files in volume disk
	#
	
	printf '%s' "${K2HR3_ROLE_YRN}"					> "${K2HR3_VOLUME_PATH}/${K2HR3_FILE_ROLE}"
	printf '%s' "${local_cuk_base64}"				> "${K2HR3_VOLUME_PATH}/${K2HR3_FILE_CUK}"
	printf '%s' "${local_cuk_base64_urlenc}"		> "${K2HR3_VOLUME_PATH}/${K2HR3_FILE_CUKENC}"
	printf '%s' "cuk=${local_cuk_base64_urlenc}"	> "${K2HR3_VOLUME_PATH}/${K2HR3_FILE_APIARG}"

	cat << EOT > "${K2HR3_VOLUME_PATH}/${K2HR3_FILE_DEINIT_SH}"
#!/bin/sh
curl -s -S -X DELETE "${K2HR3_API_SCHEMA}://${K2HR3_API_HOST}:${K2HR3_API_PORT}${K2HR3_API_URI}/${K2HR3_ROLE_YRN}?cuk=${local_cuk_base64_urlenc}"
if [ $? -ne 0 ]; then
	echo "[ERROR] Failed deletion from role member." 1>&2
	exit 1
fi
exit 0
EOT
	chmod 0500 "${K2HR3_VOLUME_PATH}/${K2HR3_FILE_DEINIT_SH}"

else
	#
	# Deletion
	#

	#
	# Call K2HR3 REST API
	#
	# Example: 
	#	curl -s -S -X DELETE "http(s)://<k2hr3 api host>:<port>/<uri>/<role yrn>?cuk=<cuk parameter>"
	#
	K2HR3_API_PARAMS=$(cat "${K2HR3_VOLUME_PATH}/${K2HR3_FILE_APIARG}" 2>/dev/null)
	if ! curl -s -S -X DELETE "${K2HR3_API_SCHEMA}://${K2HR3_API_HOST}:${K2HR3_API_PORT}${K2HR3_API_URI}/${K2HR3_ROLE_YRN}?${K2HR3_API_PARAMS}"; then
		echo "[ERROR] ${PRGNAME} : Failed deletion from role member." 1>&2
		exit 1
	fi
fi

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
