FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      openssh-server \
      iproute2 \
      procps \
      net-tools \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd /root/.ssh /var/mock /etc/kamailio /var/backups/kamailio-dispatcher /tmp/pbx-migration \
    && chmod 700 /root/.ssh

COPY bin/fs_cli /usr/local/bin/fs_cli
COPY bin/systemctl /usr/local/bin/systemctl
COPY bin/kamcmd /usr/local/bin/kamcmd
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/fs_cli /usr/local/bin/systemctl /usr/local/bin/kamcmd /usr/local/bin/entrypoint.sh \
    && sed -ri 's/^#?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config \
    && echo 'AuthorizedKeysFile .ssh/authorized_keys' >> /etc/ssh/sshd_config

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
