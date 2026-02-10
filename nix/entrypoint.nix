{ pkgs }:
pkgs.writeScript "entrypoint.sh" ''
  #!${pkgs.bash}/bin/bash
  set -e

  export HOME="/app"
  export PNPM_HOME="/app/.pnpm-global/bin"
  export PATH="$PNPM_HOME:$PATH"

  echo "Starting OpenClaw Container..."
  mkdir -p /app
  cd /app

  ${pkgs.pnpm}/bin/pnpm config set global-bin-dir "$PNPM_HOME"
  ${pkgs.pnpm}/bin/pnpm config set global-dir "/app/.pnpm-global"
  ${pkgs.pnpm}/bin/pnpm config set ignore-scripts false

  if ! command -v openclaw &> /dev/null; then
      echo "OpenClaw executable not found in $PNPM_HOME."
      echo "Installing openclaw@latest via pnpm..."
      ${pkgs.pnpm}/bin/pnpm approve-builds -g || true
      ${pkgs.pnpm}/bin/pnpm install -g openclaw@latest
      echo "Installation complete."
  else
      echo "OpenClaw is already installed."
  fi

  if [ "$#" -gt 0 ]; then
      exec "$@"
  else
      echo "Running openclaw..."
      exec openclaw
  fi
''
