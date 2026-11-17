-- Personal Hyprland overrides, owned by SrRenks/dotfiles and stowed into
-- ~/.config/hypr/user.lua. reddoted loads this file after its own config and
-- ignores it in git, so `install.sh --update` never touches it.
--
-- Anything here wins over config/hypr/*: monitors, and any binding or app the
-- rice reads at keypress time (see config/hypr/variables.lua).

-- Personal monitor layout for this laptop (gitignored):
--   eDP-1      1920x1200@60, scale 1, origin 0,0
--   HDMI-A-1   LG 29WK600 2560x1080@75, scale 1, right of the laptop
-- Same modes/scales the reddot setup used; the ultrawide is not forced into
-- its 4K@30 mode by the "highres" auto rule anymore.
hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "2560x1080@75", position = "1920x0", scale = 1, vrr = 2 })
