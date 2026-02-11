{pkgs}:
pkgs.writeShellScriptBin "wayvnc" ''
  #!/usr/bin/env bash
  set -euo pipefail

  export XDG_RUNTIME_DIR=/tmp/runtime-$(id -u)
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"

  WAYVNC=${pkgs.wayvnc}/bin/wayvnc

  if [ -n "''${WAYLAND_DISPLAY:-}" ]; then
    LOCK_FILE="$XDG_RUNTIME_DIR/wayvnc-''${WAYLAND_DISPLAY#wayland-}"
    touch "$LOCK_FILE"
    trap "rm -f '$LOCK_FILE'" EXIT
    exec "$WAYVNC" "$@"
  fi

  MAX_AVAILABLE=""
  for display in $(ls "$XDG_RUNTIME_DIR"/wayland-[0-9] 2>/dev/null | sed 's/.*wayland-//'); do
    if [ ! -f "$XDG_RUNTIME_DIR/wayvnc-$display" ]; then
      MAX_AVAILABLE=$display
    fi
  done

  if [ -z "$MAX_AVAILABLE" ]; then
    exec "$WAYVNC" "$@"
  fi

  export WAYLAND_DISPLAY="wayland-$MAX_AVAILABLE"
  LOCK_FILE="$XDG_RUNTIME_DIR/wayvnc-$MAX_AVAILABLE"
  touch "$LOCK_FILE"
  trap "rm -f '$LOCK_FILE'" EXIT

  "$WAYVNC" "$@"
''
