FROM alpine:latest

RUN apk update && apk add --no-cache \
    bash \
    bash-completion \
    coreutils \
    curl \
    gnupg \
    shadow \
    sudo \
    tar \
    xz

RUN addgroup -g 1000 nixuser && \
    adduser -D \
        -u 1000 \
        -G nixuser \
        -s /bin/bash \
        nixuser && \
    echo "nixuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p -m 0755 /nix && \
    chown nixuser:nixuser /nix

USER nixuser
WORKDIR /home/nixuser

ENV HOME=/home/nixuser \
    USER=nixuser

COPY --chown=nixuser:nixuser \
    config/nix.conf \
    /home/nixuser/.config/nix/nix.conf

RUN curl -L https://nixos.org/nix/install | bash -s -- --no-daemon

ENV PATH=/home/nixuser/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH

RUN echo '. "$HOME/.nix-profile/etc/profile.d/nix.sh"' >> ~/.bashrc

COPY --chown=nixuser:nixuser \
    config/nix-packages.txt \
    /tmp/nix-packages.txt

RUN . "$HOME/.nix-profile/etc/profile.d/nix.sh" && \
    if [ -s /tmp/nix-packages.txt ]; then \
        nix profile install $(< /tmp/nix-packages.txt); \
    fi && \
    rm -f /tmp/nix-packages.txt

COPY --chown=nixuser:nixuser \
    scripts/test-toolbox.sh \
    /usr/local/bin/test-toolbox

RUN chmod +x /usr/local/bin/test-toolbox

USER root
RUN rm -rf /var/cache/apk/*

USER nixuser
WORKDIR /home/nixuser

CMD ["bash"]
