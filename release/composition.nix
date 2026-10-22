{ pkgs, lib, config, components ? config.images }:
let
  inherit (config) redis;
  # Composition consumes caller-selected image references; Agni owns topology.
  # The defaults remain reserved placeholders until release-ledger verification.
  images = components;
  validMemory = assert lib.assertMsg (redis.memoryMiB == 40) "Only the 40 MiB Redis profile is qualified"; true;
  # Qualified release tags are selected and pinned by the Nix-Alpine ledger.
  # Podman image availability is a separate deployment/runtime gate.
  requireLocalImage = name: image:
    assert lib.assertMsg (
      builtins.isString image &&
      (builtins.match ("localhost/fatline/" + name + ":[0-9]{4}[.][0-9]{2}[.][0-9]{2}([.][0-9]+)?") image != null ||
       builtins.match ("localhost/nix-alpine/" + name + ":qualified-[0-9]{4}[.][0-9]{2}[.][0-9]{2}([.][0-9]+)?") image != null)
    ) "${name} must use a Fatline CalVer tag or Nix-Alpine qualified release tag";
    image;
  service = name: image: ''
    [Unit]
    Description=Fatline ${name}
    Requires=fatline-nginx.service
    After=fatline-nginx.service
    ConditionPathExists=%h/.config/fatline/${name}.env

    [Container]
    Image=${requireLocalImage name image}
    Pull=never
    ContainerName=fatline-${name}
    Network=fatline.network
    EnvironmentFile=%h/.config/fatline/${name}.env

    [Service]
    Restart=always

    [Install]
    WantedBy=default.target
  '';
  nginxConf = ''
    worker_processes 1;
    pid /tmp/nginx.pid;
    error_log /dev/stderr warn;
    events { worker_connections 128; }
    stream {
      upstream redis_socket { server unix:/run/redis/redis.sock; }
      server {
        listen 6379;
        proxy_pass redis_socket;
        proxy_connect_timeout 5s;
        proxy_timeout 1h;
      }
    }
  '';
  nginxUnit = ''
    [Unit]
    Description=Fatline Redis TCP-to-Unix proxy
    Requires=fatline-redis.service
    After=fatline-redis.service

    [Container]
    Image=${requireLocalImage "nginx" images.nginx}
    Pull=never
    ContainerName=fatline-nginx
    Network=fatline.network
    NetworkAlias=redis-proxy
    ReadOnly=true
    Volume=%h/.config/fatline/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    Volume=%t/fatline/redis:/run/redis
    NoNewPrivileges=true
    DropCapability=all

    [Service]
    Restart=always

    [Install]
    WantedBy=default.target
  '';
  networkUnit = ''
    [Network]
    NetworkName=fatline
    Internal=true
  '';
  redisConf = ''
    port 0
    unixsocket /run/redis/redis.sock
    unixsocketperm 770
    save ""
    appendonly no
    maxmemory ${toString redis.memoryMiB}mb
    maxmemory-policy noeviction
    aclfile /etc/redis/users.acl
    protected-mode yes
  '';
  redisUnit = ''
    [Unit]
    Description=Fatline shared Redis
    ConditionPathExists=%h/.config/fatline/redis/users.acl

    [Container]
    Image=${requireLocalImage "redis" images.redis}
    Pull=never
    ContainerName=fatline-redis
    Network=none
    ReadOnly=true
    Volume=%h/.config/fatline/redis/redis.conf:/etc/redis/redis.conf:ro
    Volume=%h/.config/fatline/redis/users.acl:/etc/redis/users.acl:ro
    Volume=%t/fatline/redis:/run/redis
    # The Redis image entrypoint is redis-server; Exec supplies its config argument.
    Exec=/etc/redis/redis.conf
    NoNewPrivileges=true
    DropCapability=all

    [Service]
    ExecStartPre=/usr/bin/install -d -m 0770 %t/fatline/redis
    Restart=always

    [Install]
    WantedBy=default.target
  '';
in assert validMemory; pkgs.runCommand "fatline-quadlet-composition" { } ''
  mkdir -p "$out/quadlets" "$out/config" "$out/metadata"
  cat > "$out/metadata/components.json" <<'EOF'
${builtins.toJSON images}
EOF
  cat > "$out/quadlets/fatline-redis.container" <<'EOF'
${redisUnit}
EOF
  cat > "$out/quadlets/fatline-nginx.container" <<'EOF'
${nginxUnit}
EOF
  cat > "$out/quadlets/fatline.network" <<'EOF'
${networkUnit}
EOF
  cat > "$out/config/nginx.conf" <<'EOF'
${nginxConf}
EOF
  cat > "$out/quadlets/fatline-logma.container" <<'EOF'
${service "logma" images.logma}
EOF
  cat > "$out/quadlets/fatline-skymill.container" <<'EOF'
${service "skymill" images.skymill}
EOF
  cat > "$out/config/redis.conf" <<'EOF'
${redisConf}
EOF
  grep -qx 'Pull=never' "$out/quadlets/fatline-redis.container"
  grep -q 'proxy_pass redis_socket;' "$out/config/nginx.conf"
  grep -qx 'Internal=true' "$out/quadlets/fatline.network"
  grep -qx 'port 0' "$out/config/redis.conf"
  grep -qx 'maxmemory 40mb' "$out/config/redis.conf"
  grep -qx 'maxmemory-policy noeviction' "$out/config/redis.conf"
  grep -qx 'aclfile /etc/redis/users.acl' "$out/config/redis.conf"
  for provider in logma skymill; do
    grep -qx 'Pull=never' "$out/quadlets/fatline-$provider.container"
    ! grep -q 'Volume=.*fatline/redis' "$out/quadlets/fatline-$provider.container"
    grep -qx 'Network=fatline.network' "$out/quadlets/fatline-$provider.container"
    grep -qx 'Requires=fatline-nginx.service' "$out/quadlets/fatline-$provider.container"
    grep -qx 'After=fatline-nginx.service' "$out/quadlets/fatline-$provider.container"
  done
''
