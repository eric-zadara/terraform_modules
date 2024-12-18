#!/bin/bash
# Wait for instance profile to be assigned
source /etc/profile.d/zadara-ec2.sh
_log() { echo "[$(date +%s)][$0]${@}" ; }
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
wait-for-instance-profile
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_DATA=$(aws ec2 describe-instances --instance-ids "${INSTANCE_ID}" | jq -c -r --arg instance_id "${INSTANCE_ID}" '.Reservations[0].Instances[] | select(.InstanceId==$instance_id)')
