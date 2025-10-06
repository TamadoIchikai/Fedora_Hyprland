# Why i switch from sway -> hyprland
- Sway window layout is kinda odd to me, the reason why i switch to a tiling Window Manager (WM) is because it is very convinient and make sense to me much more than simple floating window manager. Sway/I3 is a very stable WM but it is a manual layout tiling, i know there're scripts to automatic it but those i find isn't good enough (also hyprland animation and blurring is another things so...)

# When first booting into fedora
```bash
sudo dnf install neovim git zsh
sudo sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
chezmoi init --apply https://github.com/TamadoIchikai/Fedora_Hyprland
chsh -s $(which zsh)
```
