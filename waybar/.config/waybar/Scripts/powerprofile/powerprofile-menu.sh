#!/usr/bin/env bash

choice=$(
printf "󰌪 Power Saver\n󰗑 Balanced\n󱐋 Performance" |
rofi -dmenu -i -p "Power Profile"
)

case "$choice" in
    "󰌪 Power Saver")
        powerprofilesctl set power-saver
        ;;
    "󰗑 Balanced")
        powerprofilesctl set balanced
        ;;
    "󱐋 Performance")
        powerprofilesctl set performance
        ;;
    *)
        exit 0
        ;;
esac

pkill -RTMIN+9 waybar
