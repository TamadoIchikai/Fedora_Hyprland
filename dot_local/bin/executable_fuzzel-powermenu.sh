#!/bin/bash

SELECTION="$(printf "  - Lock\n󰙧  - Suspend\n󰒲  - Hibernate\n󰗽  - Log out\n󰜉  - Reboot\n  - Reboot to UEFI\n󱖈  - Hard reboot\n  - Shutdown" | fuzzel --dmenu -l 8 -p "Power Menu: ")"

case $SELECTION in
	*"Lock")
		sleep 0.5
		hyprlock;;
	*"Suspend")
		systemctl suspend;;
	*"Hibernate")
		systemctl hibernate;;
	*"Log out")
		hyprctl dispatch exit;;
	*"Reboot")
		systemctl reboot;;
	*"Reboot to UEFI")
		systemctl reboot --firmware-setup;;
	*"Hard reboot")
		pkexec "echo b > /proc/sysrq-trigger";;
	*"Shutdown")
		systemctl poweroff;;
esac
