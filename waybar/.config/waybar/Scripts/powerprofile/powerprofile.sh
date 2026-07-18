#!/usr/bin/env bash

profile=$(powerprofilesctl get)

case "$profile" in
    power-saver)
        icon="󰌪"
        label="Power Saver"
        ;;
    balanced)
        icon="󰗑"
        label="Balanced"
        ;;
    performance)
        icon="󱐋"
        label="Performance"
        ;;
    *)
        icon="?"
        label="Unknown"
        ;;
esac

printf '{"text":"%s","tooltip":"Power Profile: %s"}\n' \
    "$icon" \
    "$label"
