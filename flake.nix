{
  description = "OpenClaw Docker Container with Runtime Install & Browser Support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    forAllSystems = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"];
  in {
    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {inherit system;};

        # Browser Dependencies for Playwright/Puppeteer
        browserLibs = with pkgs; [
          chromium
          bashInteractive
          cacert
          chromium
          curl
          liberation_ttf
          noto-fonts-color-emoji
          git
          jq
          novnc
          socat
          (python3.withPackages
            (ps: [ps.websockify]))
        ];

        # Runtime Entrypoint
        entrypoint = pkgs.writeScript "entrypoint.sh" ''
          #!${pkgs.bash}/bin/bash
          set -e

          # Set HOME to /app so config files are written there
          export HOME="/app"

          # Configure PNPM Global Path
          export PNPM_HOME="/app/.pnpm-global/bin"
          export PATH="$PNPM_HOME:$PATH"

          echo "Starting OpenClaw Container..."

          # Ensure /app exists
          mkdir -p /app
          cd /app

          # Configure pnpm explicitly to use the writable path
          ${pkgs.pnpm}/bin/pnpm config set global-bin-dir "$PNPM_HOME"
          ${pkgs.pnpm}/bin/pnpm config set global-dir "/app/.pnpm-global"

          # Ensure scripts run (fixes "Ignored build scripts" warning)
          ${pkgs.pnpm}/bin/pnpm config set ignore-scripts false

          # Check for OpenClaw
          if ! command -v openclaw &> /dev/null; then
              echo "OpenClaw executable not found in $PNPM_HOME."
              echo "Installing openclaw@latest via pnpm..."

              # Install globally
              ${pkgs.pnpm}/bin/pnpm install -g openclaw@latest

              # Attempt to approve builds if pnpm v9+ requires it
              ${pkgs.pnpm}/bin/pnpm approve-builds -g || true

              echo "Installation complete."
          else
              echo "OpenClaw is already installed."
          fi

          # Execute Command
          if [ "$#" -gt 0 ]; then
              exec "$@"
          else
              echo "Running openclaw..."
              exec openclaw
          fi
        '';
      in {
        dockerImage = pkgs.dockerTools.streamLayeredImage {
          name = "openclaw";
          tag = "latest";

          contents =
            [
              pkgs.dockerTools.fakeNss
              pkgs.bashInteractive
              pkgs.coreutils
              pkgs.gnused # Required by pnpm wrappers
              pkgs.git
              pkgs.nodejs_22
              pkgs.pnpm
              pkgs.python3
              pkgs.vips
              pkgs.pkg-config
              pkgs.gcc
              pkgs.gnumake
              pkgs.cacert
            ]
            ++ browserLibs;

          extraCommands = ''
            mkdir -p app
            mkdir -p tmp
            chmod 1777 tmp
          '';

          config = {
            # Use Entrypoint so arguments are passed to the script, not overriding it
            Entrypoint = ["${entrypoint}"];
            # Default command if no arguments are provided
            Cmd = [];

            WorkingDir = "/app";
            Env = [
              "NODE_ENV=production"
              "HOME=/app"
              "PNPM_HOME=/app/.pnpm-global/bin"
              "PATH=/app/.pnpm-global/bin:/bin:/usr/bin:${pkgs.nodejs_22}/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              # LD_LIBRARY_PATH is essential for non-Nix binaries (like Playwright browsers) to find system libs
              "LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath browserLibs}"
              "FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf"
              "FONTCONFIG_PATH=${pkgs.fontconfig.out}/etc/fonts"
            ];
            ExposedPorts = {
              "3000/tcp" = {};
            };
          };
        };
      }
    );
  };
}
