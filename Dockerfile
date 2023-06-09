FROM ubuntu:20.04 as base


### Stage 1 - add/remove packages ###

# Ensure scripts are available for use in next command
COPY ./container/root/scripts/* /scripts/
COPY ./container/root/usr/local/bin/* /usr/local/bin/

# - Symlink variant-specific scripts to default location
# - Upgrade base security packages, then clean packaging leftover
# - Add S6 for zombie reaping, boot-time coordination, signal transformation/distribution: @see https://github.com/just-containers/s6-overlay#known-issues-and-workarounds
# - Add goss for local, serverspec-like testing
RUN /bin/bash -e /scripts/ubuntu_apt_config.sh && \
    /bin/bash -e /scripts/ubuntu_apt_cleanmode.sh && \
    ln -s /scripts/clean_ubuntu.sh /clean.sh && \
    ln -s /scripts/security_updates_ubuntu.sh /security_updates.sh && \
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    /bin/bash -e /security_updates.sh && \
    apt-get install -yqq \
      curl \
      gpg \
      apt-transport-https \
    && \
    /bin/bash -e /scripts/install_s6.sh && \
    /bin/bash -e /scripts/install_goss.sh && \
    apt-get remove --purge -yq \
        curl \
        gpg \
    && \
    /bin/bash -e /clean.sh && \
    # out of order execution, has a dpkg error if performed before the clean script, so keeping it here,
    apt-get remove --purge --auto-remove systemd --allow-remove-essential -y

# Overlay the root filesystem from this repo
COPY ./container/root /




### Stage 2 --- collapse layers ###

FROM scratch
COPY --from=base / .

# Use in multi-phase builds, when an init process requests for the container to gracefully exit, so that it may be committed
# Used with alternative CMD (worker.sh), leverages supervisor to maintain long-running processes
ENV SIGNAL_BUILD_STOP=99 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_KILL_FINISH_MAXTIME=5000 \
    S6_KILL_GRACETIME=3000

RUN goss -g goss.base.yaml validate

# NOTE: intentionally NOT using s6 init as the entrypoint
# This would prevent container debugging if any of those service crash

# ==================================================================
RUN apt-get update -y
RUN apt-get install curl -y
        # ====terminal===
RUN apt-get install xfce4-terminal -y
RUN update-alternatives --config x-terminal-emulator
RUN yes 2| update-alternatives --config x-terminal-emulator
        # ====terminal===
        # ====chinese===
RUN apt install language-pack-zh-hant -y
RUN locale-gen
RUN apt install -y \
gnome-user-docs-zh-hans \
language-pack-gnome-zh-hans \
fcitx \
fcitx-pinyin \
fcitx-table-wubi \
fcitx-chewing -y
RUN apt install ttf-wqy-zenhei
        # ====chinese===
RUN apt-get update && apt-get install -y gnupg2
RUN sed -i '$a\deb http://cn.archive.ubuntu.com/ubuntu/ bionic universe' /etc/apt/sources.list
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32
RUN apt-get update -y
RUN apt-get install vnc4server -y
RUN apt-get install xfce4 -y
RUN yes 16313302 | vncserver
RUN vncserver -kill :1
RUN sed -i 's/$vncPort = .*/$vncPort = 5900;/g' /usr/bin/vncserver
RUN mv /root/.vnc/xstartup /root/.vnc/xstartup.bak
COPY ./shell_conf/xstartup /root/.vnc
RUN chmod +x /root/.vnc/xstartup
RUN sed -i '$a\if [ -f /root/conf/start_ssh.sh ]; then ' /root/.bashrc \
&& sed -i '$a\      /root/conf/start_ssh.sh' /root/.bashrc \
&& sed -i '$a\fi' /root/.bashrc

RUN apt-get update && apt-get install -y dialog openssh-server ssh vim
RUN echo "root:16313302" | chpasswd  \
&& sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
&& sed -i 's/^#\(PermitRootLogin.*\)/\1/' /etc/ssh/sshd_config
RUN /etc/init.d/ssh start
EXPOSE 22

ENV SYSTEMPATH=/run.d
COPY ./shell_conf/rund/* ${SYSTEMPATH}
RUN chmod +x /${SYSTEMPATH}/*.sh

ENV DOCKER_INSTALL_SAHLL=/root/conf
RUN mkdir ${DOCKER_INSTALL_SAHLL}
COPY ./shell_conf/install_shell/*  ${DOCKER_INSTALL_SAHLL}
RUN chmod +x ${DOCKER_INSTALL_SAHLL}/*.sh
RUN sh ${DOCKER_INSTALL_SAHLL}/install_browser.sh


CMD ["/bin/bash", "/run.sh"]
