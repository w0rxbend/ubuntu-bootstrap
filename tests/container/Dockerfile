# Throwaway "fresh Zorin OS 18" image for `tests/run-tests.sh --container`: ubuntu:24.04 plus the CLI part of what a
# fresh Zorin install ships (zorin-baseline.txt, which also documents the delta), Zorin's os-release/lsb-release,
# and the host user (same name, uid and home path, so ${HOME}-based profile paths line up).
# The sudoers drop-in below exists only inside this image; it gives the test user the passwordless `sudo -n`
# that fluxion's privileged steps need. Nothing here touches the host.
# The repo is NOT baked in: run-tests.sh git-clones the host repo (committed HEAD) into ~/.zorin-bootstrap at run
# time, exactly as the README quick start does on a new machine.
FROM ubuntu:24.04

ARG USER_NAME=tester
ARG USER_UID=1000
ARG USER_GID=1000

# Build-time only (ARG, not ENV): at run time fluxion must meet the same environment as in a desktop terminal,
# where nothing sets DEBIAN_FRONTEND.
ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8 TERM=xterm-256color

COPY zorin-baseline.txt /tmp/zorin-baseline.txt
RUN apt-get update \
 && grep -v '^[[:space:]]*#' /tmp/zorin-baseline.txt | xargs apt-get install -y --no-install-recommends \
 && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen \
 && rm -rf /var/lib/apt/lists/* /tmp/zorin-baseline.txt

# Zorin OS 18.1 identity (copied from a Zorin 18.1 install). Zorin ships its own base-files
# (13ubuntu10.4+zorin2), so Ubuntu's base-files never overwrites these there; hold it here so 00-base's
# full-upgrade cannot restore Ubuntu's os-release either.
RUN printf '%s\n' \
      'PRETTY_NAME="Zorin OS 18.1"' 'NAME="Zorin OS"' 'VERSION_ID="18"' 'VERSION="18.1"' \
      'VERSION_CODENAME=noble' 'ID=zorin' 'ID_LIKE="ubuntu debian"' 'HOME_URL="https://zorin.com/os/"' \
      'SUPPORT_URL="https://help.zorin.com/"' 'BUG_REPORT_URL="https://zorin.com/os/feedback/"' \
      'PRIVACY_POLICY_URL="https://zorin.com/legal/privacy/"' 'UBUNTU_CODENAME=noble' 'LOGO=zorin-logo' \
      > /usr/lib/os-release \
 && printf '%s\n' 'DISTRIB_ID=Zorin' 'DISTRIB_RELEASE=18' 'DISTRIB_CODENAME=noble' \
      'DISTRIB_DESCRIPTION="Zorin OS 18.1"' > /etc/lsb-release \
 && apt-mark hold base-files >/dev/null

# ubuntu:24.04 ships a user "ubuntu" with uid 1000; replace it with the host user.
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
 && if ! getent group "$USER_GID" >/dev/null; then groupadd -g "$USER_GID" "$USER_NAME"; fi \
 && useradd -m -u "$USER_UID" -g "$USER_GID" -s /bin/bash "$USER_NAME" \
 && printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USER_NAME" > "/etc/sudoers.d/90-$USER_NAME" \
 && chmod 0440 "/etc/sudoers.d/90-$USER_NAME"

USER $USER_NAME
# A login shell would set these; `docker run` does not.
ENV USER=$USER_NAME LOGNAME=$USER_NAME SHELL=/bin/bash
WORKDIR /home/$USER_NAME
