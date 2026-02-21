#!/usr/bin/env bash
set -euo pipefail

mkdir -p /var/run/sshd /root/.ssh /var/mock /etc/kamailio /var/backups/kamailio-dispatcher /tmp/pbx-migration
chmod 700 /root/.ssh

if [[ -f /seed/authorized_keys ]]; then
  cp /seed/authorized_keys /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi

echo "${CHANNEL_COUNT:-0}" > /var/mock/channels_count
echo "${REG_COUNT:-10}" > /var/mock/registrations_count
echo "${ROLE:-mock}" > /var/mock/role

if [[ ! -f /etc/kamailio/dispatcher.list ]]; then
  echo "# initial dispatcher" > /etc/kamailio/dispatcher.list
fi

touch /var/mock/kamcmd.log

exec /usr/sbin/sshd -D -e
