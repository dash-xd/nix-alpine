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
    pkgs.txt \
    /tmp/pkgs.txt

RUN . "$HOME/.nix-profile/etc/profile.d/nix.sh" && \
    nix-env -f '<nixpkgs>' -i $(cat /tmp/pkgs.txt) && \
    rm -f /tmp/pkgs.txt

USER root

RUN rm -rf /var/cache/apk/*

USER nixuser
WORKDIR /home/nixuser

CMD ["bash"]
