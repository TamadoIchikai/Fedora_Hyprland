#!/usr/bin/env python3
"""Saved Wi-Fi secret for the Quickshell Wi-Fi menu (Wifi.qml).

usage: wifi_secret.py password SSID   -> prints the saved key
       wifi_secret.py qr SSID         -> prints a "WIFI:" join QR code, one row of
                                         0/1 modules per line (1 = dark)

The NetworkManager profile is found by SSID, since profile names can differ
(e.g. a trailing space). The key never goes on a command line or to a file.
QR codes use libqrencode (qrencode-libs) through ctypes: no extra packages.
Exit codes: 1 = no saved profile, 2 = can't make a QR (enterprise network).
"""
import ctypes
import subprocess
import sys


def nm(*args: str) -> str:
    return subprocess.run(["nmcli", "-e", "no", *args],
                          capture_output=True, text=True).stdout.rstrip("\n")


def find_profile(ssid: str) -> str | None:
    for line in nm("-g", "UUID,TYPE", "connection", "show").splitlines():
        uuid, _, kind = line.partition(":")
        if kind == "802-11-wireless" and \
                nm("-g", "802-11-wireless.ssid", "connection", "show", uuid) == ssid:
            return uuid
    return None


def get(uuid: str, field: str, secret: bool = False) -> str:
    return nm(*(["-s"] if secret else []), "-g", field, "connection", "show", uuid)


def wifi_secret(uuid: str) -> tuple[str, str]:
    """(QR auth type, key): WPA covers WPA/WPA2/WPA3-Personal."""
    mgmt = get(uuid, "802-11-wireless-security.key-mgmt")
    if mgmt in ("wpa-psk", "sae"):
        return "WPA", get(uuid, "802-11-wireless-security.psk", secret=True)
    if mgmt == "none":
        return "WEP", get(uuid, "802-11-wireless-security.wep-key0", secret=True)
    if mgmt == "":
        return "nopass", ""
    return "", ""  # wpa-eap etc.: no QR format for these


def qr_rows(text: str) -> list[str]:
    class QRcode(ctypes.Structure):
        _fields_ = [("version", ctypes.c_int), ("width", ctypes.c_int),
                    ("data", ctypes.POINTER(ctypes.c_ubyte))]

    lib = ctypes.CDLL("libqrencode.so.4")
    lib.QRcode_encodeString.restype = ctypes.POINTER(QRcode)
    lib.QRcode_encodeString.argtypes = [ctypes.c_char_p, ctypes.c_int,
                                        ctypes.c_int, ctypes.c_int, ctypes.c_int]
    lib.QRcode_free.argtypes = [ctypes.POINTER(QRcode)]
    # version auto, level M (1), 8-bit mode (2), case sensitive
    ptr = lib.QRcode_encodeString(text.encode(), 0, 1, 2, 1)
    if not ptr:
        sys.exit(3)
    qr = ptr.contents
    w = qr.width
    rows = ["".join("1" if qr.data[y * w + x] & 1 else "0" for x in range(w))
            for y in range(w)]
    lib.QRcode_free(ptr)
    return rows


def escape(value: str) -> str:
    for c in '\\;,:"':
        value = value.replace(c, "\\" + c)
    return value


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in ("password", "qr"):
        sys.exit(__doc__)
    mode, ssid = sys.argv[1], sys.argv[2]
    uuid = find_profile(ssid)
    if uuid is None:
        sys.exit(1)
    auth, key = wifi_secret(uuid)
    if mode == "password":
        print(key, end="")
        return
    if not auth:
        sys.exit(2)
    payload = f"WIFI:T:{auth};S:{escape(ssid)};"
    if auth != "nopass":
        payload += f"P:{escape(key)};"
    print("\n".join(qr_rows(payload + ";")))


if __name__ == "__main__":
    main()
