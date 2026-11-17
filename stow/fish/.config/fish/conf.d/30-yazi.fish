# dotfiles · yazi as the picker for everything
#
# Yazi is the default way to look at a directory, and the default way to choose
# a file for another command. Three entry points, all bound here:
#
#   y     (the function)  open yazi, cd to wherever you quit
#   yy    (the function)  pick files, drop them on the command line
#   Ctrl+O                same as yy, one keystroke
#   Alt+Y                 same as y
#
# The GUI/file-manager side of "yazi by default" lives outside fish: see
# config/xdg/yazi.desktop and the xdg-mime call in install.sh.

if status is-interactive; and type -q yazi
    bind \co yy
    bind -M insert \co yy

    bind \ey y
    bind -M insert \ey y
end
