{pkgs}:
pkgs.writeScript "entrypoint.sh" ''
  #!${pkgs.bash}/bin/bash

  export HOME="/app"
  export PNPM_HOME="/app/.pnpm-global/bin"
  export PATH="$PNPM_HOME:$PATH"
  PID_FILE="/tmp/openclaw.pid"
  RESTART_FLAG="/tmp/openclaw-need-restart"

  mkdir -p /app
  cd /app

  # 配置 pnpm (仅在第一次运行时需要，也可保留)
  ${pkgs.pnpm}/bin/pnpm config set global-bin-dir "$PNPM_HOME"
  ${pkgs.pnpm}/bin/pnpm config set global-dir "/app/.pnpm-global"

  # 首次安装检查
  if ! command -v openclaw &> /dev/null; then
      echo "Installing openclaw..."
      ${pkgs.pnpm}/bin/pnpm install -g openclaw@latest
  fi

  cleanup() {
      echo "Stopping..."
      [ -f "$PID_FILE" ] && kill $(cat "$PID_FILE") 2>/dev/null
      rm -f "$PID_FILE" "$RESTART_FLAG"
      exit 0
  }
  trap cleanup SIGTERM SIGINT

  while true; do
      rm -f "$RESTART_FLAG"

      echo "Starting openclaw..."
      if [ "$#" -gt 0 ]; then
          "$@" &
      else
          openclaw gateway &
      fi

      # 写入 PID
      echo ''$! > "$PID_FILE"
      echo "Openclaw is running with PID: ''$(cat "$PID_FILE")"

      # 等待进程结束 (pkill 会让 wait 结束)
      wait ''$(cat "$PID_FILE") || echo "Process interrupted"

      # 检查是否存在重启标志文件
      if [ -f "$RESTART_FLAG" ]; then
          echo "Restart flag detected. Restarting..."
          rm -f "$RESTART_FLAG"
          continue
      else
          echo "Process exited normally. Cleaning up."
          rm -f "$PID_FILE"
          exit 0
      fi
  done
''
