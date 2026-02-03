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
        chromiumWrapper = pkgs.writeShellScriptBin "chromium" ''
          # 1. 环境准备
          export XDG_RUNTIME_DIR=/tmp/runtime-$(id -u)
          mkdir -p "$XDG_RUNTIME_DIR"
          chmod 700 "$XDG_RUNTIME_DIR"

          export WLR_BACKENDS=headless
          export WLR_LIBINPUT_NO_DEVICES=1
          export WLR_NO_HARDWARE_CURSORS=1
          export WLR_HEADLESS_OUTPUTS=1

          # 2. 定义清理函数
          cleanup() {
            echo "检测到主程序退出，正在清理 wayvnc..."
            # 杀掉该脚本启动的所有后台进程
            if [ -n "$WAYVNC_PID" ]; then
              echo "正在杀掉 wayvnc 进程 $WAYVNC_PID..."
              kill $WAYVNC_PID 2>/dev/null
              # 防止 wayvnc 是 wrapper 脚本，尝试杀掉子进程
              pkill -P $WAYVNC_PID 2>/dev/null || true
            fi

            # 兜底：杀掉所有 wayvnc 进程
            pkill -f wayvnc 2>/dev/null || true

            if [ -n "$CAGE_PID" ]; then
              kill $CAGE_PID 2>/dev/null
            fi
            kill $(jobs -p) 2>/dev/null
          }

          # 绑定脚本退出信号（无论正常退出还是被中断）
          trap cleanup EXIT

          # 记录启动前的 Socket 文件
          OLD_SOCKETS=""
          if [ -d "$XDG_RUNTIME_DIR" ]; then
             OLD_SOCKETS=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null || true)
          fi

          # 3. 启动 cage 并在后台运行
          ${pkgs.cage}/bin/cage -s -- ${pkgs.chromium}/bin/chromium \
            --ozone-platform=wayland \
            --enable-features=WaylandWindowDecorations \
            --no-sandbox "$@" &
          CAGE_PID=$!

          ls -la "$XDG_RUNTIME_DIR"
          # 4. 动态检测 Wayland Socket
          echo "等待 Cage 启动并创建 Wayland Socket..."
          MAX_RETRIES=50
          COUNT=0
          FOUND_SOCKET=""

          while [ -z "$FOUND_SOCKET" ]; do
            sleep 0.1
            COUNT=$((COUNT + 1))
            if [ "$COUNT" -ge "$MAX_RETRIES" ]; then
              echo "错误：Cage 启动超时，未发现新的 Wayland Socket"
              exit 1
            fi

            # 检查 Cage 进程是否还在运行
            if ! kill -0 $CAGE_PID 2>/dev/null; then
               echo "错误：Cage 进程意外退出"
               exit 1
            fi

            # 扫描当前 Socket
            CURRENT_SOCKETS=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null || true)

            for s in $CURRENT_SOCKETS; do
               IS_NEW=1
               for old in $OLD_SOCKETS; do
                 if [ "$s" = "$old" ]; then
                   IS_NEW=0
                   break
                 fi
               done

               if [ "$IS_NEW" -eq 1 ]; then
                 FOUND_SOCKET="$s"
                 break
               fi
            done
          done

          export WAYLAND_DISPLAY=$(basename "$FOUND_SOCKET")
          echo "检测到 Wayland Display: $WAYLAND_DISPLAY"

          # 5. 启动 wayvnc 并在后台运行
          # 等待 Chromium 窗口初始化，避免 vncviewer 连接时因分辨率抖动导致崩溃
          sleep 2
          ${pkgs.wayvnc}/bin/wayvnc 0.0.0.0 5900 --log-level=info &
          WAYVNC_PID=$!

          # 6. 等待主进程结束
          # 只要 cage (及其内部的浏览器) 退出，脚本就会继续往下执行到达 cleanup
          wait $CAGE_PID
        '';

        # Browser Dependencies for Playwright/Puppeteer
        browserLibs =
          [chromiumWrapper]
          ++ fonts
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

              # Attempt to approve builds if pnpm v9+ requires it
              ${pkgs.pnpm}/bin/pnpm approve-builds -g || true

              # Install globally
              ${pkgs.pnpm}/bin/pnpm install -g openclaw@latest

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
              "FONTCONFIG_FILE=${fontConfig}"
              "FONTCONFIG_PATH=${pkgs.fontconfig.out}/etc/fonts"
              "AGENT_BROWSER_EXECUTABLE_PATH=${chromiumWrapper}/bin/chromium"
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
