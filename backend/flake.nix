{
  description = "SelfPrivacy Tor VirtualBox Test Image with Real Backend";

  inputs = {
    # Use the same nixpkgs as selfprivacy-api to avoid package incompatibilities
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # SelfPrivacy REST API
    selfprivacy-api = {
      url = "git+https://git.selfprivacy.org/SelfPrivacy/selfprivacy-rest-api.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, selfprivacy-api }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Minimal SelfPrivacy module for Tor-only testing
      selfprivacyTorModule = { config, pkgs, lib, ... }:
      let
        redis-sp-api-srv-name = "sp-api";
        selfprivacy-graphql-api = selfprivacy-api.packages.${system}.default;
        workerPython = pkgs.python312.withPackages (ps: [ selfprivacy-graphql-api ps.huey ]);
      in
      {
        # Basic system
        system.stateVersion = "25.11";
        networking.hostName = "selfprivacy-tor";
        time.timeZone = "UTC";

        # Enable Tor with hidden service
        services.tor = {
          enable = true;
          settings = {
            HiddenServiceDir = "/var/lib/tor/hidden_service";
            HiddenServicePort = [
              "80 127.0.0.1:80"
              "443 127.0.0.1:443"
            ];
          };
        };

        # Redis for SelfPrivacy API
        services.redis.package = pkgs.valkey;
        services.redis.servers.${redis-sp-api-srv-name} = {
          enable = true;
          save = [
            [ 30 1 ]
            [ 10 10 ]
          ];
          port = 0; # Unix socket only
          settings = {
            notify-keyspace-events = "KEA";
          };
        };

        # User for API
        users.users.selfprivacy-api = {
          isSystemUser = true;
          group = "selfprivacy-api";
        };
        users.groups.selfprivacy-api = {};
        users.groups.redis-sp-api.members = [ "selfprivacy-api" "root" ];

        # SelfPrivacy API service (simplified for testing)
        systemd.services.selfprivacy-api = {
          description = "SelfPrivacy GraphQL API";
          after = [ "network-online.target" "redis-sp-api.service" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          environment = {
            HOME = "/root";
            PYTHONUNBUFFERED = "1";
            TEST_MODE = "true";  # Enable test mode
          };
          path = with pkgs; [
            coreutils
            gnutar
            xz.bin
            gzip
            gitMinimal
          ];
          serviceConfig = {
            User = "root";
            ExecStart = "${selfprivacy-graphql-api}/bin/app.py";
            Restart = "always";
            RestartSec = "5";
          };
        };

        # Huey worker for background tasks
        systemd.services.selfprivacy-api-worker = {
          description = "SelfPrivacy API Task Worker";
          after = [ "network-online.target" "redis-sp-api.service" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          environment = {
            HOME = "/root";
            PYTHONUNBUFFERED = "1";
            TEST_MODE = "true";
          };
          path = with pkgs; [
            coreutils
            gnutar
            xz.bin
            gzip
            gitMinimal
          ];
          serviceConfig = {
            User = "root";
            ExecStart = "${workerPython}/bin/python -m huey.bin.huey_consumer selfprivacy_api.task_registry.huey";
            Restart = "always";
            RestartSec = "5";
          };
        };

        # Nginx reverse proxy - HTTP for Tor (no TLS needed for .onion)
        services.nginx = {
          enable = true;

          virtualHosts."onion" = {
            listen = [{ addr = "0.0.0.0"; port = 80; }];
            default = true;

            locations."/" = {
              root = pkgs.writeTextDir "index.html" ''
                <!DOCTYPE html>
                <html>
                <head><title>SelfPrivacy Tor Test</title></head>
                <body>
                  <h1>SelfPrivacy over Tor - Real Backend</h1>
                  <p>This server is running the actual SelfPrivacy GraphQL API.</p>
                  <p>Your .onion address is in: <code>/var/lib/tor/hidden_service/hostname</code></p>
                  <h2>API Endpoints:</h2>
                  <ul>
                    <li><a href="/graphql">GraphQL API</a></li>
                    <li><a href="/api/version">API Version</a></li>
                  </ul>
                </body>
                </html>
              '';
              index = "index.html";
            };

            # Proxy GraphQL to SelfPrivacy API
            locations."/graphql" = {
              proxyPass = "http://127.0.0.1:5050";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
              '';
            };

            # Proxy REST API endpoints
            locations."/api" = {
              proxyPass = "http://127.0.0.1:5050";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
              '';
            };
          };
        };

        # Show onion address on console login
        services.getty.helpLine = lib.mkForce ''

          =====================================================
          SelfPrivacy Tor Test VM - Real Backend

          To get your .onion address, run:
            cat /var/lib/tor/hidden_service/hostname

          API Status: systemctl status selfprivacy-api
          API Logs: journalctl -u selfprivacy-api -f

          Default login: root (no password)
          =====================================================
        '';

        # Allow root login without password for testing
        users.users.root = {
          initialHashedPassword = "";
          password = null;
        };
        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "yes";
            PermitEmptyPasswords = "yes";
          };
        };
        security.pam.services.sshd.allowNullPassword = true;

        # Firewall - only allow local connections (Tor handles external)
        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 ]; # SSH for local access
        };

        # Useful packages
        environment.systemPackages = with pkgs; [
          curl
          htop
          vim
          tor
          jq
          valkey  # Redis CLI
        ];

        # Display onion address after boot
        systemd.services.show-onion = {
          description = "Display onion address";
          wantedBy = [ "multi-user.target" ];
          after = [ "tor.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            echo "Waiting for Tor to generate .onion address..."
            for i in $(seq 1 120); do
              if [ -f /var/lib/tor/hidden_service/hostname ]; then
                echo ""
                echo "=========================================="
                echo "Your .onion address is:"
                cat /var/lib/tor/hidden_service/hostname
                echo "=========================================="
                echo ""
                break
              fi
              sleep 1
            done
          '';
        };

        # NixOS settings
        nix.settings = {
          experimental-features = [ "nix-command" "flakes" ];
        };

        # Required directories
        systemd.tmpfiles.rules = [
          "d /var/lib/selfprivacy 0755 root root - -"
          "d /etc/nixos 0755 root root - -"
        ];
      };
    in
    {
      # NixOS configuration for installation
      nixosConfigurations.selfprivacy-tor-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          selfprivacyTorModule
          ({ modulesPath, ... }: {
            imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
            boot.loader.grub.enable = true;
            boot.loader.grub.device = "/dev/sda";
            fileSystems."/" = {
              device = "/dev/disk/by-label/nixos";
              fsType = "ext4";
            };
            virtualisation.virtualbox.guest.enable = true;
          })
        ];
      };

      # Build ISO installer
      packages.${system}.default = (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ({ pkgs, lib, modulesPath, ... }: {
            # Include the selfprivacy flake config in the ISO
            isoImage.contents = [
              {
                source = self;
                target = "/selfprivacy-config";
              }
            ];

            # Enable SSH with empty password for automated install
            services.openssh = {
              enable = true;
              settings = {
                PermitRootLogin = "yes";
                PermitEmptyPasswords = "yes";
              };
            };

            # Allow empty passwords through PAM
            security.pam.services.sshd.allowNullPassword = true;

            # Set root to have no password
            users.users.root = {
              initialHashedPassword = "";
              password = null;
            };

            services.getty.helpLine = lib.mkForce ''

              =====================================================
              SelfPrivacy Tor Installer ISO - Real Backend
              SSH enabled - root with no password
              =====================================================
            '';

            environment.systemPackages = with pkgs; [ git vim parted ];
          })
        ];
      }).config.system.build.isoImage;

    };
}
