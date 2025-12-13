#!/bin/bash

SELECTION="$(printf "1 - Lock\n2 - Suspend\n3 - Hibernate\n4 - Log out\n5 - Reboot\n6 - Reboot to UEFI\n7 - Hard reboot\n8 - Shutdown" | fuzzel --dmenu -l 8 -p "Power Menu: ")"

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
		hyprshutdown -t 'Restarting...' --post-cmd 'reboot';;
	*"Reboot to UEFI")
		systemctl reboot --firmware-setup;;
	*"Hard reboot")
		pkexec "echo b > /proc/sysrq-trigger";;
	*"Shutdown")
		hyprshutdown -t 'Shutting down...' --post-cmd 'shutdown -P 0';;
esac
