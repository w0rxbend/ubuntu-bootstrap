# Throwaway Ubuntu 24.04 (noble) image for `tests/run-tests.sh --container`: the non-GUI modules run here
# exactly as on the host (same user name, uid and home path, so ${HOME}-based profile paths line up).
# The sudoers drop-in below exists only inside this image; it gives the test user the passwordless `sudo -n`
# that fluxion's privileged steps need. Nothing here touches the host.
FROM ubuntu:24.04

ARG USER_NAME=tester
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 TERM=dumb

# Minimal Zorin-like base: what 00-base expects to find before its first apt run, plus the shared libraries
# of a dynamically linked fluxion dev build (libyaml, libssl, libpcre2, zlib). The release binary is static.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      sudo ca-certificates curl wget git gnupg python3 python3-yaml unzip xz-utils file \
      libyaml-0-2 libssl3t64 libpcre2-8-0 zlib1g libgcc-s1 tzdata locales \
 && rm -rf /var/lib/apt/lists/*

# ubuntu:24.04 ships a user "ubuntu" with uid 1000; replace it with the host user.
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
 && if ! getent group "$USER_GID" >/dev/null; then groupadd -g "$USER_GID" "$USER_NAME"; fi \
 && useradd -m -u "$USER_UID" -g "$USER_GID" -s /bin/bash "$USER_NAME" \
 && printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USER_NAME" > "/etc/sudoers.d/90-$USER_NAME" \
 && chmod 0440 "/etc/sudoers.d/90-$USER_NAME"

USER $USER_NAME
WORKDIR /home/$USER_NAME
