#!/bin/bash
set -euo pipefail
DOTS=/home/renks/Projects/dotfiles
. "$DOTS/lib/ui.sh"
MENU_ROWS=(
  "head||presets||"
  "preset|preset:desktop|desktop|74 pacotes|base-devel,git,curl,pipewire"
  "head|grp:base|base|4|base-devel,git,curl,jq"
  "pkg|base-devel|base-devel|build tools|"
  "pkg|git|git|version control|"
  "pkg|curl|curl|http|"
  "pkg|jq|jq|json|"
  "head|grp:audio|audio|1|pipewire"
  "pkg|pipewire|pipewire|sound server|"
  "head||terminal||"
  "unit|fish|fish|configs do fish|"
  "action||iniciar||"
)
MENU_ON=(base-devel git)
MENU_VISIBLE=12
ui_menu "o que instalar?"
echo "ACTION=$MENU_ACTION"
if [ ${#MENU_PICKED[@]} -gt 0 ]; then printf "PICKED=%s\n" "${MENU_PICKED[*]}"; else echo "PICKED="; fi
