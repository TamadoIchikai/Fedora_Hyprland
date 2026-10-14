#!/usr/bin/env bash
source "$HOME/.config/abstractions/wm.sh"

SELECTION="$(printf "  - Lock\n󰙧  - Suspend\n󰒲  - Hibernate\n󰗽  - Log out\n󰜉  - Reboot\n  - Reboot to UEFI\n  - Shutdown" | fuzzel --dmenu -l 7 -p "Power Menu: ")"

case "$SELECTION" in
	*"Lock")
		sleep 0.5
		WM_lock;;
	*"Suspend")
		systemctl suspend
		;;
	*"Hibernate")
		systemctl hibernate
		;;
	*"Log out")
		WM_exit
		;;
	*"Reboot")
		systemctl reboot
		;;
	*"Reboot to UEFI")
		systemctl reboot --firmware-setup
		;;
	*"Shutdown")
		systemctl poweroff
		;;
esac
