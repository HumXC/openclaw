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

        entrypoint = import ./nix/entrypoint.nix {inherit pkgs;};
        chromium-cage = import ./nix/chromium-cage.nix {inherit pkgs;};
        wayvnc-wrap = import ./nix/wayvnc-wrap.nix {inherit pkgs;};

        fonts = with pkgs; [
          liberation_ttf
          noto-fonts-color-emoji
          noto-fonts-cjk-sans
          noto-fonts-cjk-serif
          wqy_zenhei
        ];

        fontConfig = pkgs.makeFontsConf {
          fontDirectories = fonts;
        };

        browserLibs =
          fonts
          ++ (with pkgs; [
            wayvnc
            bashInteractive
            cacert
            curl
            git
            jq
            novnc
            socat
            gnugrep
            procps
            (python3.withPackages
              (ps: [ps.websockify]))
          ]);
      in {
        dockerImage = pkgs.dockerTools.streamLayeredImage {
          name = "openclaw";
          tag = "latest";

          contents =
            [
              wayvnc-wrap
              chromium-cage

              pkgs.which
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
              pkgs.cage
              pkgs.cmake
              pkgs.glibc_multi
              pkgs.findutils
              pkgs.gawk
              pkgs.busybox
            ]
            ++ browserLibs;

          extraCommands = ''
            mkdir -p app
            mkdir -p tmp
            chmod 1777 tmp
          '';

          config = {
            Entrypoint = ["${entrypoint}"];
            DefaultCommand = [];

            WorkingDir = "/app";
            Env = [
              "NODE_ENV=production"
              "HOME=/app"
              "PNPM_HOME=/app/.pnpm-global/bin"
              "PATH=/app/.pnpm-global/bin:/bin:/usr/bin:${pkgs.nodejs_22}/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath browserLibs}"
              "FONTCONFIG_FILE=${fontConfig}"
              "FONTCONFIG_PATH=${pkgs.fontconfig.out}/etc/fonts"
              "AGENT_BROWSER_EXECUTABLE_PATH=${chromium-cage}/bin/chromium"
              "AGENT_BROWSER_STATE=/app/agent-browser-init.json"
            ];
            ExposedPorts = {
              "5900/tcp" = {};
            };
          };
        };
      }
    );
  };
}
