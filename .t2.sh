#!/bin/bash
set -uo pipefail
DOTS=/home/renks/Projects/dotfiles
. "$DOTS/lib/ui.sh"
MENU_ROWS=( "pkg|a|a|desc|" "action||iniciar||" )
MENU_ON=()
MENU_VISIBLE=5
ui_menu "test"
echo "ACTION=$MENU_ACTION PICKED=[${MENU_PICKED[*]:-}]"
