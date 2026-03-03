# Why i switch from sway -> hyprland
- The reason why i switch to a tiling Window Manager (WM) is because it is very convinient and make sense to me much more than simple floating window manager. Sway/I3 is a very stable WM but it is a manual tiling WM, i know there're scripts to have an automatic layout but those i found isn't good enough. First tiling WM i used was PopOS!, their automatic tiling WM was very good and stable, i intended to move to Cosmic desktop when it finally stable but it took too long, so i make my own hyprland setup with some of my favourite apps.

# When first booting into [fedora everything](https://fedoraproject.org/misc#minimal) 
- Connect to ethernet (assume enp3s0 is ethernet port)
```bash
nmcli d
sudo nmcli device connect enp3s0
```
- Install stuff
```bash
sudo dnf install neovim git zsh vim 
sudo sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
chezmoi init --apply https://github.com/TamadoIchikai/Fedora_Hyprland
chsh -s $(which zsh)
.~/.config/installSH/install.sh
```

# Autologin via tty
```bash
sudo systemctl edit getty@tty1.service
```
- Then add below command before the line `## command below this line will be discarded`
```bash
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin tamadoichikai --noclear %I $TERM
```
- NOTICE that `tamadoichikai` is my current username, remember to check with whoami.

# Fix wifi issues currently in fedora everything
- Somehow iwlwifi driver isn't in fedora everything so we only need to install it
```bash
sudo dnf install iwlwifi\*
sudo modprobe iwlwifi
sudo reboot
```
- If there's other issues check hardware with
```bash
sudo dmesg | grep -i ucode
```
