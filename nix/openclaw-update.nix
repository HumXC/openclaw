{pkgs}:
pkgs.writeScriptBin "openclaw-update" ''
  #!${pkgs.bash}/bin/bash
  set -e

  export HOME="/app"
  export PNPM_HOME="/app/.pnpm-global/bin"
  export PATH="$PNPM_HOME:$PATH"

  RESTART=false
  while [[ "$1" ]]; do
      case "$1" in
          --restart|-r)
              RESTART=true
              ;;
      esac
      shift
  done

  output=$(${pkgs.pnpm}/bin/pnpm outdated -g openclaw 2>&1)

  if [ -z "$output" ]; then
      echo "openclaw 已是最新版本"
      exit 0
  fi

  ${pkgs.pnpm}/bin/pnpm update -g openclaw

  if [ "$RESTART" = true ]; then
      openclaw-restart
  fi
''
