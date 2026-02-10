{pkgs}:
pkgs.writeScriptBin "openclaw-restart" ''
  #!${pkgs.bash}/bin/bash
  set -e

  touch /tmp/openclaw-need-restart
  [ -f /tmp/openclaw.pid ] && kill $(cat /tmp/openclaw.pid)
  echo "已触发 openclaw gateway 重启"
''
