{pkgs}:
pkgs.writeShellScriptBin "chromium" ''
  export XDG_RUNTIME_DIR=/tmp/runtime-$(id -u)
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"

  case "$*" in
    *--headless*|*--headless=*|*--dump-dom*|*--print-to-pdf*)
      exec ${pkgs.chromium}/bin/chromium "$@"
      ;;
    *)
      export WLR_BACKENDS=headless
      export WLR_LIBINPUT_NO_DEVICES=1
      export WLR_NO_HARDWARE_CURSORS=1
      export WLR_HEADLESS_OUTPUTS=1
      exec ${pkgs.cage}/bin/cage -s -- ${pkgs.chromium}/bin/chromium \
        --ozone-platform=wayland \
        --enable-features=WaylandWindowDecorations \
        --no-sandbox \
        --disable-blink-features=AutomationControlled \
        --disable-infobars \
        --window-size=1920,1080 \
        "$@"
      ;;
  esac
''
