#!/usr/bin/python3
# this is to make sure default python runs instead of a conda env

"""
hyprmode - Display Mode Switcher for Hyprland
Phase 2: Interactive menu with display mode switching via fuzzel
VERSION: v0.2.0 (Fuzzel Edition)
"""

import json
import subprocess
import sys
from pathlib import Path
from typing import Optional

def get_monitors() -> dict:
    """
    Execute hyprctl monitors -j and parse monitor data.
    Also gets disabled monitors from hyprctl monitors all -j
    Returns: {
        'laptop': {'name': 'eDP-1', 'width': 1920, 'height': 1080, 'refreshRate': 60.0} or None,
        'external': {'name': 'HDMI-A-1', 'width': 2560, 'height': 1440, 'refreshRate': 144.0} or None
    }
    """
    try:
        # Try to get all monitors (including disabled)
        result = subprocess.run(
            ["hyprctl", "monitors", "all", "-j"],
            capture_output=True,
            text=True,
            check=True,
            timeout=5
        )
        monitors_data = json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError, subprocess.TimeoutExpired):
        # Fallback to regular monitors command (only active monitors)
        try:
            result = subprocess.run(
                ["hyprctl", "monitors", "-j"],
                capture_output=True,
                text=True,
                check=True,
                timeout=5
            )
            monitors_data = json.loads(result.stdout)
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Failed to execute hyprctl: {e}")
        except json.JSONDecodeError as e:
            raise RuntimeError(f"Failed to parse hyprctl output: {e}")
        except subprocess.TimeoutExpired:
            raise RuntimeError("hyprctl command timed out")
    except FileNotFoundError:
        raise RuntimeError("hyprctl not found - is Hyprland running?")
    
    if not monitors_data:
        raise RuntimeError("No monitors detected")
    
    laptop: Optional[dict] = None
    external: Optional[dict] = None
    
    for monitor in monitors_data:
        monitor_info = {
            'name': monitor.get('name', 'Unknown'),
            'width': monitor.get('width', 0),
            'height': monitor.get('height', 0),
            'refreshRate': monitor.get('refreshRate', 0.0),
            'scale': monitor.get('scale', 1.0),
            'disabled': monitor.get('disabled', False)
        }
        
        # Identify laptop monitor (contains "eDP")
        if "eDP" in monitor_info['name']:
            laptop = monitor_info
        else:
            # Only set external if it's the first one we find
            if external is None:
                external = monitor_info
    
    return {
        'laptop': laptop,
        'external': external
    }

def send_notification(message: str, urgent: bool = False) -> None:
    """Send desktop notification using notify-send"""
    try:
        cmd = ["notify-send", "HyprMode", message]
        if urgent:
            cmd.insert(1, "-u")
            cmd.insert(2, "critical")
        subprocess.run(cmd, check=False, timeout=2)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

def clear_mirror_state(laptop: Optional[dict], external: Optional[dict]) -> dict:
    """
    Clear any existing mirror relationship and restore native monitor specs.
    Returns refreshed monitor data after reload.
    """
    try:
        if external:
            subprocess.run(["hyprctl", "keyword", "monitor", f"{external['name']},disable"], timeout=5, stderr=subprocess.DEVNULL)
        if laptop:
            subprocess.run(["hyprctl", "keyword", "monitor", f"{laptop['name']},disable"], timeout=5, stderr=subprocess.DEVNULL)
        
        import time
        time.sleep(0.3)
        subprocess.run(["hyprctl", "reload"], timeout=5, stderr=subprocess.DEVNULL)
        time.sleep(0.3)
        return get_monitors()
    except Exception:
        return {'laptop': laptop, 'external': external}

def apply_laptop_only(laptop: Optional[dict], external: Optional[dict]) -> None:
    if not laptop:
        raise RuntimeError("Laptop monitor not detected - cannot enable")
    monitors = clear_mirror_state(laptop, external)
    laptop = monitors['laptop']
    external = monitors['external']
    try:
        laptop_config = f"{laptop['name']},{laptop['width']}x{laptop['height']}@{laptop['refreshRate']:.0f},auto,{laptop['scale']}"
        subprocess.run(["hyprctl", "keyword", "monitor", laptop_config], check=True, timeout=5)
        if external:
            subprocess.run(["hyprctl", "keyword", "monitor", f"{external['name']},disable"], check=True, timeout=5)
        send_notification("Switched to Laptop Only mode")
    except Exception as e:
        raise RuntimeError(f"Failed to apply laptop only mode: {e}")

def apply_external_only(laptop: Optional[dict], external: dict) -> None:
    if not external:
        raise RuntimeError("External monitor not detected - cannot enable")
    monitors = clear_mirror_state(laptop, external)
    laptop = monitors['laptop']
    external = monitors['external']
    try:
        external_config = f"{external['name']},{external['width']}x{external['height']}@{external['refreshRate']:.0f},auto,{external['scale']}"
        subprocess.run(["hyprctl", "keyword", "monitor", external_config], check=True, timeout=5)
        if laptop:
            subprocess.run(["hyprctl", "keyword", "monitor", f"{laptop['name']},disable"], check=True, timeout=5)
        send_notification("Switched to External Only mode")
    except Exception as e:
        raise RuntimeError(f"Failed to apply external only mode: {e}")

def apply_extend(laptop: Optional[dict], external: dict) -> None:
    if not laptop or not external:
        raise RuntimeError("Both laptop and external monitors required for extend mode")
    monitors = clear_mirror_state(laptop, external)
    laptop = monitors['laptop']
    external = monitors['external']
    try:
        laptop_config = f"{laptop['name']},{laptop['width']}x{laptop['height']}@{laptop['refreshRate']:.0f},0x0,{laptop['scale']}"
        subprocess.run(["hyprctl", "keyword", "monitor", laptop_config], check=True, timeout=5)
        external_config = f"{external['name']},{external['width']}x{external['height']}@{external['refreshRate']:.0f},auto-right,{external['scale']}"
        subprocess.run(["hyprctl", "keyword", "monitor", external_config], check=True, timeout=5)
        send_notification("Switched to Extend mode")
    except Exception as e:
        raise RuntimeError(f"Failed to apply extend mode: {e}")

def apply_mirror(laptop: Optional[dict], external: dict) -> None:
    if not laptop or not external:
        raise RuntimeError("Both laptop and external monitors required for mirror mode")
    monitors = clear_mirror_state(laptop, external)
    laptop = monitors['laptop']
    external = monitors['external']
    try:
        import time
        mirror_width, mirror_height, mirror_refresh = external['width'], external['height'], external['refreshRate']
        laptop_config = f"{laptop['name']},{mirror_width}x{mirror_height}@{mirror_refresh:.0f},0x0,{laptop['scale']}"
        subprocess.run(["hyprctl", "keyword", "monitor", laptop_config], check=True, timeout=5)
        time.sleep(0.3)
        external_config = f"{external['name']},{mirror_width}x{mirror_height}@{mirror_refresh:.0f},0x0,{external['scale']},mirror,{laptop['name']}"
        subprocess.run(["hyprctl", "keyword", "monitor", external_config], check=True, timeout=5)
        send_notification(f"Mirror mode applied - using {mirror_width}x{mirror_height}@{mirror_refresh:.0f}Hz")
    except Exception as e:
        raise RuntimeError(f"Failed to apply mirror mode: {e}")

def main():
    try:
        monitors = get_monitors()
    except RuntimeError as e:
        send_notification(str(e), urgent=True)
        sys.exit(1)
        
    options = [
        "󰌢  Laptop Only",
        "󰹑  External Only",
        "󰍺  Extend",
        "  Mirror"
    ]
    menu_text = "\n".join(options)

    # Call fuzzel via subprocess
    try:
        result = subprocess.run(
            ["fuzzel", "--dmenu", "-l", "4", "-p", "Display Mode: "],
            input=menu_text,
            text=True,
            capture_output=True,
            check=True
        )
        selection = result.stdout.strip()
    except subprocess.CalledProcessError:
        # User hit escape or closed fuzzel
        sys.exit(0)
    except FileNotFoundError:
        send_notification("fuzzel not found. Please install fuzzel.", urgent=True)
        sys.exit(1)

    laptop = monitors['laptop']
    external = monitors['external']

    try:
        if "Laptop Only" in selection:
            if not laptop:
                send_notification("Laptop display not detected.", urgent=True)
                return
            apply_laptop_only(laptop, external)
        elif "External Only" in selection:
            if not external:
                send_notification("No external monitor detected", urgent=True)
                return
            apply_external_only(laptop, external)
        elif "Extend" in selection:
            if not laptop or not external:
                send_notification("Both laptop and external monitors needed for extend", urgent=True)
                return
            apply_extend(laptop, external)
        elif "Mirror" in selection:
            if not laptop or not external:
                send_notification("Both laptop and external monitors needed for mirror", urgent=True)
                return
            apply_mirror(laptop, external)
    except RuntimeError as e:
        send_notification(str(e), urgent=True)

if __name__ == "__main__":
    main()
