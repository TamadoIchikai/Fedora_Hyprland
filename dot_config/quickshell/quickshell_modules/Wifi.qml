// Wi-Fi menu (replaces the old fuzzel `networkmanager_dmenu`, no longer in the dotfiles).
//
// Opened from the waybar network module:
//   qs -c quickshell_modules ipc call wifi toggle      (also: open / close / rescan)
// Opened from fuzzel (~/.local/share/applications/wifi-menu.desktop), centred and wider:
//   qs -c quickshell_modules ipc call wifi openCentered
//
// Wi-Fi and Ethernet use Quickshell.Networking (NetworkManager over D-Bus).
// Saved VPN / WireGuard profiles come from `nmcli` (Quickshell has no VPN API).
// Typing filters the list (networks, VPNs and actions like "rescan"); Enter
// activates the highlighted (first) row.
// The UI only exists while open: closing destroys it and stops the scanner.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland

Scope {
    id: root

    // Colours (shared with AltTab.qml)
    readonly property color bgColor: "#353535"
    readonly property color hoverColor: "#5D5D5D"
    readonly property color borderColor: "#5D5D5D"
    readonly property color activeBorderColor: "#FFCB66"   // connected row
    readonly property color textColor: "#E6E6E6"
    readonly property color dimTextColor: "#8F8F8F"
    readonly property color fieldColor: "#2B2B2B"
    readonly property color errorColor: "#E06C75"
    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"
    readonly property string iconFontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 11

    // Layout
    readonly property int menuWidth: 400
    // Centred mode (opened from fuzzel): wider, in the middle of the screen.
    readonly property int centeredWidth: 560
    readonly property int rowHeight: 36
    readonly property int maxVisibleRows: 10
    // Centres the menu on the waybar Wi-Fi icon (icon centre is 256 px from the
    // right screen edge; 256 - menuWidth / 2).
    readonly property int marginRight: 56
    readonly property int marginBottom: 8

    property bool open: false
    // true: middle of the screen (fuzzel); false: above the waybar Wi-Fi icon.
    property bool centered: false
    // Network waiting for a password (null = password box hidden).
    property WifiNetwork pskNetwork: null
    property string pskError: ""
    // A click on the waybar icon first clears the focus grab (closing the menu)
    // and then runs `toggle`; don't reopen right away in that case.
    property double grabClosedAt: 0

    // Search text (lower case) and highlighted row (-1 = none).
    property string query: ""
    property int selIndex: -1
    onQueryChanged: selIndex = query !== "" && entries.length > 0 ? 0 : -1

    // Rows that failed to connect, by key ("wifi:<name>", "vpn:<uuid>").
    property var failed: ({})

    function setFailed(key: string, value: bool): void {
        const f = Object.assign({}, failed);
        if (value)
            f[key] = true;
        else
            delete f[key];
        failed = f;
    }

    readonly property var devices: Networking.devices.values
    readonly property WifiDevice wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevices: devices.filter(d => d.type === DeviceType.Wired)

    // Connected first, then saved, then strongest. Hidden SSIDs are skipped.
    readonly property var networks: {
        if (!wifiDevice || !Networking.wifiEnabled)
            return [];
        return wifiDevice.networks.values
            .filter(n => n.name !== "")
            .sort((a, b) => (b.connected - a.connected)
                || (b.known - a.known)
                || (b.signalStrength - a.signalStrength)
                || a.name.localeCompare(b.name));
    }

    // ---- VPN (nmcli) ----

    // [{ name, uuid, type, state }] for VPN / WireGuard profiles saved on disk.
    // Runtime profiles (/run/..., e.g. a tunnel created by another program) are
    // skipped so the menu never tears down something it doesn't own.
    property var vpns: []
    // uuid of the VPN being switched (shows "…").
    property string vpnBusy: ""

    // `nmcli -t -e yes` escapes ':' and '\' with a backslash.
    function splitNmcli(line: string): var {
        const fields = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) {
                cur += line[++i];
            } else if (c === ":") {
                fields.push(cur);
                cur = "";
            } else {
                cur += c;
            }
        }
        fields.push(cur);
        return fields;
    }

    function parseVpns(text: string): var {
        return text.split("\n").filter(l => l !== "").map(l => {
            const [name, uuid, type, state, file] = splitNmcli(l);
            return { name, uuid, type, state, file };
        }).filter(c => (c.type === "vpn" || c.type === "wireguard") && c.file.startsWith("/etc/"));
    }

    function refreshVpns(): void {
        if (!vpnList.running)
            vpnList.running = true;
    }

    function toggleVpn(v: var): void {
        if (!v || vpnAction.running)
            return;
        setFailed(`vpn:${v.uuid}`, false);
        vpnBusy = v.uuid;
        const up = v.state !== "activated" && v.state !== "activating";
        vpnAction.command = ["nmcli", "connection", up ? "up" : "down", "uuid", v.uuid];
        vpnAction.running = true;
    }

    Process {
        id: vpnList
        command: ["nmcli", "-t", "-e", "yes", "-f", "NAME,UUID,TYPE,STATE,FILENAME", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: root.vpns = root.parseVpns(text)
        }
    }

    Process {
        id: vpnAction
        stderr: StdioCollector { id: vpnErr }
        onExited: (code, status) => {
            if (code !== 0) {
                console.warn(`wifi: VPN switch failed: ${vpnErr.text}`);
                root.setFailed(`vpn:${root.vpnBusy}`, true);
            }
            root.vpnBusy = "";
            root.refreshVpns();
        }
    }

    // Keep VPN and networking state fresh while the menu is open
    // (e.g. "activating" -> "activated").
    Timer {
        interval: 2000
        repeat: true
        running: root.open
        triggeredOnStart: true
        onTriggered: {
            root.refreshVpns();
            root.refreshNetworking();
        }
    }

    // ---- Networking on/off (right-click the Wi-Fi switch) ----

    // NetworkManager's global switch (`nmcli networking`): off drops every
    // connection, not just Wi-Fi. Quickshell.Networking has no API for it.
    property bool networkingEnabled: true

    function refreshNetworking(): void {
        if (!netState.running)
            netState.running = true;
    }

    function toggleNetworking(): void {
        if (netToggle.running)
            return;
        netToggle.command = ["nmcli", "networking", networkingEnabled ? "off" : "on"];
        netToggle.running = true;
    }

    Process {
        id: netState
        command: ["nmcli", "networking"]
        stdout: StdioCollector {
            onStreamFinished: root.networkingEnabled = text.trim() !== "disabled"
        }
    }

    Process {
        id: netToggle
        stderr: StdioCollector { id: netErr }
        onExited: (code, status) => {
            if (code !== 0)
                console.warn(`wifi: nmcli networking failed: ${netErr.text}`);
            root.refreshNetworking();
            root.refreshVpns();
        }
    }

    // ---- Show saved Wi-Fi password ----

    // SSID whose password is shown in place of its name ("" = none).
    property string revealName: ""
    // The password (or "…" while loading). Only kept while shown.
    property string revealPassword: ""

    function toggleReveal(ssid: string): void {
        if (revealName === ssid) {
            hideReveal();
            return;
        }
        revealName = ssid;
        revealPassword = "…";
        pwProc.running = false;
        pwProc.command = ["python3", root.secretScript, "password", ssid];
        pwProc.running = true;
    }

    function hideReveal(): void {
        pwProc.running = false;
        revealName = "";
        revealPassword = "";
    }

    Process {
        id: pwProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.revealName !== "")
                    root.revealPassword = text !== "" ? text : "(no password saved)";
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.revealName !== "")
                root.revealPassword = "(not found)";
        }
    }

    // ---- Wi-Fi QR code (right-click the eye / row) ----

    // Finds the saved profile by SSID and prints its key or a join QR code.
    readonly property string secretScript: Quickshell.shellPath("scripts/wifi_secret.py")

    // SSID whose QR code is shown under its row ("" = none).
    property string qrName: ""
    // QR modules: one string of 0/1 per row ([] while loading).
    property var qrRows: []
    property string qrError: ""

    function toggleQr(ssid: string): void {
        if (qrName === ssid) {
            hideQr();
            return;
        }
        qrName = ssid;
        qrRows = [];
        qrError = "";
        qrProc.running = false;
        qrProc.command = ["python3", root.secretScript, "qr", ssid];
        qrProc.running = true;
    }

    function hideQr(): void {
        qrProc.running = false;
        qrName = "";
        qrRows = [];
        qrError = "";
    }

    Process {
        id: qrProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.qrName !== "")
                    root.qrRows = text.split("\n").filter(r => r !== "");
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.qrName !== "")
                root.qrError = code === 2 ? "No QR code for enterprise networks" : "Saved profile not found";
        }
    }

    // ---- Forget confirmation ----

    // SSID whose trash was clicked once: a second click within 3 s forgets it.
    property string forgetArmed: ""
    // Hovering or moving to another row cancels.
    onSelIndexChanged: forgetArmed = ""

    function requestForget(n: WifiNetwork): void {
        if (!n)
            return;
        if (forgetArmed === n.name) {
            forgetArmed = "";
            n.forget();
        } else {
            forgetArmed = n.name;
            forgetTimeout.restart();
        }
    }

    Timer {
        id: forgetTimeout
        interval: 3000
        onTriggered: root.forgetArmed = ""
    }

    // ---- Rescan ----

    // Spins the refresh icon while NetworkManager rescans.
    property bool rescanning: false

    function rescan(): void {
        if (rescanning || !wifiDevice || !Networking.wifiEnabled)
            return;
        rescanning = true;
        Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"]);
        rescanTimer.restart();
    }

    Timer {
        id: rescanTimer
        interval: 3000
        onTriggered: root.rescanning = false
    }

    // ---- Rows ----

    // Actions: listed at the bottom of the list, and ranked into search results.
    readonly property var actions: [
        {
            kind: "action", key: "rescan", icon: "󰑐", label: "Rescan networks",
            keywords: ["rescan", "refresh", "scan", "reload"],
            run: () => root.rescan()
        },
        {
            kind: "action", key: "wifi-toggle", icon: Networking.wifiEnabled ? "󰖪" : "󰖩",
            label: Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on",
            keywords: ["wifi", "wi-fi", "toggle", "turn", "enable", "disable"],
            run: () => { if (Networking.wifiHardwareEnabled) Networking.wifiEnabled = !Networking.wifiEnabled; }
        },
        {
            kind: "action", key: "networking", icon: root.networkingEnabled ? "󰲛" : "󰛳",
            label: root.networkingEnabled ? "Turn networking off" : "Turn networking on",
            keywords: ["networking", "network", "offline", "online", "airplane"],
            run: () => root.toggleNetworking()
        },
        {
            kind: "action", key: "warp", icon: "󰴴", label: "Toggle Cloudflare WARP",
            keywords: ["warp", "cloudflare", "1.1.1.1", "vpn"],
            // Same script as right-clicking the waybar Wi-Fi/WARP icon; it
            // notifies and refreshes the waybar icon itself.
            run: () => {
                Quickshell.execDetached([`${Quickshell.env("HOME")}/.config/waybar/scripts/warp-waybar.sh`, "toggle"]);
                root.close();
            }
        },
        {
            kind: "action", key: "show-password", icon: "󰈈", label: "Show Wi-Fi password",
            keywords: ["password", "pass", "key", "psk", "show"],
            run: () => {
                const n = root.networks.find(n => n.connected);
                if (n)
                    root.toggleReveal(n.name);
            }
        },
        {
            kind: "action", key: "show-qr", icon: "󰐲", label: "Show Wi-Fi QR code",
            keywords: ["qr", "qrcode", "share", "scan-to-join"],
            run: () => {
                const n = root.networks.find(n => n.connected);
                if (n)
                    root.toggleQr(n.name);
            }
        },
        {
            kind: "action", key: "settings", icon: "󰒓", label: "More settings…",
            keywords: ["settings", "more", "editor", "advanced", "connections", "nm-connection-editor"],
            run: () => root.openSettings()
        }
    ]

    // All rows in display order: Ethernet, VPN, Wi-Fi.
    readonly property var allEntries: [
        ...wiredDevices.map(d => ({ kind: "wired", key: `wired:${d.name}`, dev: d, label: `Ethernet (${d.name})` })),
        ...vpns.map(v => ({ kind: "vpn", key: `vpn:${v.uuid}`, vpn: v, label: v.name })),
        ...networks.map(n => ({ kind: "wifi", key: `wifi:${n.name}`, net: n, label: n.name }))
    ]

    // 3: name starts with the query, 2: a word does, 1: contains it, 0: no match.
    // Hidden keywords only count when they start with the query.
    function keywordScore(k: string, q: string): int {
        return k.startsWith(q) ? 3 : 0;
    }

    function score(text: string, q: string): int {
        const t = text.toLowerCase();
        if (t.startsWith(q))
            return 3;
        if (t.split(/[\s\-_.()]+/).some(w => w.startsWith(q)))
            return 2;
        return t.includes(q) ? 1 : 0;
    }

    // Rows shown: everything, or the matches sorted best first (stable).
    readonly property var liveEntries: {
        const q = query;
        // No search: every row, then all actions at the bottom (also reachable
        // by scrolling / arrow keys, not only by typing).
        if (q === "")
            return [...allEntries, ...actions];
        const scored = [];
        // Actions need 2+ letters so a single key doesn't bury the networks.
        if (q.length >= 2) {
            for (const a of actions) {
                const s = Math.max(score(a.label, q), ...a.keywords.map(k => keywordScore(k, q)));
                if (s > 0)
                    scored.push({ e: a, s, i: scored.length });
            }
        }
        for (const e of allEntries) {
            const extra = e.kind === "vpn" ? [e.vpn.type, "vpn"] : e.kind === "wired" ? ["ethernet", "wired"] : [];
            const s = Math.max(score(e.label, q), ...extra.map(k => keywordScore(k, q)));
            if (s > 0)
                scored.push({ e, s, i: scored.length });
        }
        return scored.sort((a, b) => (b.s - a.s) || (a.i - b.i)).map(x => x.e);
    }

    // While a password box is open the order is frozen: a re-sort (signal
    // strengths change often) would rebuild the rows and wipe the typed text.
    property var frozenEntries: null
    readonly property var entries: pskNetwork !== null && frozenEntries !== null ? frozenEntries : liveEntries

    readonly property int wifiCount: networks.length

    // Opens the password box under the network's row.
    function askPassword(n: WifiNetwork, error: string): void {
        if (pskNetwork === null)
            frozenEntries = liveEntries;
        pskError = error;
        pskNetwork = n;
    }

    function cancelPassword(): void {
        pskNetwork = null;
        pskError = "";
        frozenEntries = null;
    }

    function show(): void {
        centered = false;
        showMenu();
    }

    function showCentered(): void {
        centered = true;
        showMenu();
    }

    function showMenu(): void {
        cancelPassword();
        query = "";
        selIndex = -1;
        failed = {};
        open = true;
    }

    function close(): void {
        open = false;
        hideReveal();
        hideQr();
        forgetArmed = "";
        cancelPassword();
    }

    function toggle(): void {
        if (open)
            close();
        else if (Date.now() - grabClosedAt > 400)
            show();
    }

    function openSettings(): void {
        Quickshell.execDetached(["nm-connection-editor"]);
        close();
    }

    function isSecured(n: WifiNetwork): bool {
        return !!n && n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }

    function isEnterprise(n: WifiNetwork): bool {
        return [WifiSecurityType.Wpa2Eap, WifiSecurityType.WpaEap, WifiSecurityType.Wpa3SuiteB192,
            WifiSecurityType.Leap, WifiSecurityType.DynamicWep].includes(n.security);
    }

    function securityLabel(n: WifiNetwork): string {
        switch (n?.security) {
        case WifiSecurityType.Open: return "Open";
        case WifiSecurityType.Owe: return "OWE";
        case WifiSecurityType.WpaPsk: return "WPA";
        case WifiSecurityType.Wpa2Psk: return "WPA2";
        case WifiSecurityType.Sae: return "WPA3";
        case WifiSecurityType.WpaEap:
        case WifiSecurityType.Wpa2Eap: return "802.1X";
        case WifiSecurityType.Wpa3SuiteB192: return "WPA3-EAP";
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep: return "WEP";
        case WifiSecurityType.Leap: return "LEAP";
        default: return "";
        }
    }

    // signalStrength is 0..1 (tolerate 0..100 too).
    function signalIcon(strength: real): string {
        const s = strength > 1 ? strength / 100 : strength;
        return ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"][Math.max(0, Math.min(4, Math.round(s * 4)))];
    }

    function wiredDetail(d: var): string {
        if (!d.hasLink)
            return "Unplugged";
        return d.connected ? `${d.linkSpeed} Mb/s` : "Disconnected";
    }

    function vpnDetail(v: var): string {
        if (v.state === "activating")
            return "Connecting";
        return v.type === "wireguard" ? "WireGuard" : "VPN";
    }

    function detailOf(e: var): string {
        switch (e?.kind) {
        case "wired": return wiredDetail(e.dev);
        case "vpn": return vpnDetail(e.vpn);
        case "wifi": return securityLabel(e.net);
        default: return "";
        }
    }

    function activate(n: WifiNetwork): void {
        if (!n || n.stateChanging)
            return;
        // Clicking the row whose password box is open closes it.
        if (pskNetwork === n) {
            cancelPassword();
            return;
        }
        setFailed(`wifi:${n.name}`, false);
        if (n.connected) {
            n.disconnect();
        } else if (n.known || !isSecured(n)) {
            n.connect();
        } else {
            askPassword(n, isEnterprise(n) ? "Enterprise network: use More settings" : "");
        }
    }

    function activateEntry(e: var): void {
        switch (e?.kind) {
        case "action":
            e.run();
            break;
        case "wired": {
            const net = e.dev.network;
            if (!e.dev.hasLink || !net || net.stateChanging)
                return;
            if (net.connected)
                net.disconnect();
            else
                net.connect();
            break;
        }
        case "vpn":
            toggleVpn(e.vpn);
            break;
        case "wifi":
            activate(e.net);
            break;
        }
    }

    function submitPsk(psk: string): void {
        if (!pskNetwork || psk.length === 0)
            return;
        pskNetwork.connectWithPsk(psk);
        cancelPassword();
    }

    IpcHandler {
        target: "wifi"

        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
        function openCentered(): void { root.showCentered(); }
        function close(): void { root.close(); }
        function rescan(): void { root.rescan(); }
    }

    // Scan only while the menu is open.
    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.open
        when: root.wifiDevice !== null
        restoreMode: Binding.RestoreNone
    }

    // A row: icon | name | detail column | optional trash button.
    component NetRow: Rectangle {
        id: row

        property string icon
        property string label
        property string detail
        property int detailWidth: 0
        property bool connected
        property bool busy
        property bool failed
        property bool selected
        property bool canForget
        property bool usable: true
        // Show-password eye (saved Wi-Fi): shown on hover, or while revealed.
        property bool canReveal
        property bool revealed
        property string revealText
        property bool qrShown
        // Trash clicked once: waiting for the confirming second click.
        property bool forgetArmed
        signal activated()
        signal forgetRequested()
        signal hovered()
        signal revealToggled()
        signal qrToggled()

        implicitHeight: root.rowHeight
        radius: 8
        color: selected && usable ? root.hoverColor : "transparent"
        border.width: 2
        border.color: connected ? root.activeBorderColor : "transparent"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.usable
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: row.hovered()
            // Right click on a saved Wi-Fi: QR code.
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    if (row.canReveal)
                        row.qrToggled();
                } else {
                    row.activated();
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 10

            Text {
                Layout.preferredWidth: 22
                horizontalAlignment: Text.AlignHCenter
                text: row.icon
                color: row.connected ? root.activeBorderColor : root.textColor
                opacity: row.usable ? 1 : 0.5
                // Non-"Mono" Nerd Font: icons keep their full size.
                font.family: root.iconFontFamily
                font.pointSize: root.fontSize + 3
            }

            // Name, or the password while revealed. A password too long for the
            // row scrolls right-to-left (pause, scroll, pause, jump back).
            Item {
                id: labelBox

                Layout.fillWidth: true
                implicitHeight: labelText.implicitHeight
                clip: true

                readonly property real overflow: Math.max(0, labelText.implicitWidth - width)

                Text {
                    id: labelText

                    anchors.verticalCenter: parent.verticalCenter
                    width: row.revealed ? implicitWidth : labelBox.width
                    text: row.revealed ? row.revealText : row.label
                    elide: row.revealed ? Text.ElideNone : Text.ElideRight
                    maximumLineCount: 1
                    color: row.revealed ? root.activeBorderColor
                        : row.usable ? root.textColor : root.dimTextColor
                    font.family: root.fontFamily
                    font.pointSize: root.fontSize
                    font.bold: row.connected && !row.revealed
                }

                SequentialAnimation {
                    running: row.revealed && labelBox.overflow > 0
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) labelText.x = 0

                    PropertyAction { target: labelText; property: "x"; value: 0 }
                    PauseAnimation { duration: 1200 }
                    NumberAnimation {
                        target: labelText
                        property: "x"
                        to: -labelBox.overflow
                        duration: Math.max(800, labelBox.overflow * 30)
                    }
                    PauseAnimation { duration: 1200 }
                }
            }

            // Detail column (security / status). On a saved Wi-Fi row the eye
            // replaces it on hover: closed eye = hidden, open eye = shown.
            Item {
                Layout.preferredWidth: row.detailWidth > 0 ? row.detailWidth : detailText.implicitWidth
                Layout.fillHeight: true

                readonly property bool showEye: !row.forgetArmed && row.canReveal
                    && (row.selected || row.revealed || row.qrShown)

                Text {
                    id: detailText
                    anchors.fill: parent
                    visible: !parent.showEye
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: row.forgetArmed ? "Forget?" : row.busy ? "…" : row.failed ? "Failed" : row.detail
                    color: row.failed || row.forgetArmed ? root.errorColor : root.dimTextColor
                    font.bold: row.forgetArmed
                    font.family: root.fontFamily
                    font.pointSize: root.fontSize - 1
                }

                Rectangle {
                    visible: parent.showEye
                    // Centred on the (right-aligned) security text it replaces.
                    x: parent.width - Math.max(detailText.contentWidth, width) / 2 - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 20
                    radius: 6
                    color: eyeMouse.containsMouse ? root.bgColor : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: row.revealed ? "󰈈" : "󰈉"
                        color: row.revealed || eyeMouse.containsMouse ? root.activeBorderColor : root.textColor
                        font.family: root.iconFontFamily
                        font.pointSize: root.fontSize + 1
                    }

                    MouseArea {
                        id: eyeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // Left: show password. Right: QR code.
                        onClicked: mouse => mouse.button === Qt.RightButton ? row.qrToggled() : row.revealToggled()
                    }
                }
            }

            // Trash: forget the saved profile. Space is always reserved so columns stay aligned.
            Item {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    // Always shown on saved networks, so they're easy to tell apart.
                    visible: row.canForget
                    // Armed: solid red until confirmed or cancelled.
                    color: row.forgetArmed || trashMouse.containsMouse ? root.errorColor : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰆴"
                        color: row.forgetArmed || row.selected || trashMouse.containsMouse ? root.textColor : root.dimTextColor
                        font.family: root.fontFamily
                        font.pointSize: root.fontSize
                    }

                    MouseArea {
                        id: trashMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: row.forgetRequested()
                    }
                }
            }
        }
    }

    component FooterButton: Rectangle {
        id: btn

        property string text
        property string family: root.fontFamily
        property int pointSize: root.fontSize - 1
        signal clicked()

        implicitWidth: btnText.implicitWidth + 20
        implicitHeight: 28
        radius: 8
        color: btnMouse.containsMouse ? root.hoverColor : "transparent"
        border.width: 1
        border.color: root.borderColor

        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.text
            color: root.textColor
            font.family: btn.family
            font.pointSize: btn.pointSize
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.clicked()
        }
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            // No anchors = the compositor centres the surface.
            anchors.bottom: !root.centered
            anchors.right: !root.centered
            margins.right: root.centered ? 0 : root.marginRight
            margins.bottom: root.centered ? 0 : root.marginBottom
            WlrLayershell.exclusionMode: root.centered ? ExclusionMode.Ignore : ExclusionMode.Normal
            color: "transparent"
            WlrLayershell.namespace: "wifi"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            implicitWidth: root.centered ? root.centeredWidth : root.menuWidth
            implicitHeight: content.implicitHeight + 24

            HyprlandFocusGrab {
                active: true
                windows: [win]
                onCleared: {
                    root.grabClosedAt = Date.now();
                    root.close();
                }
            }

            FontMetrics {
                id: detailMetrics
                font.family: root.fontFamily
                font.pointSize: root.fontSize - 1
            }

            // Width of the detail column: fits the longest label shown (no empty space).
            readonly property real detailWidth: Math.max(detailMetrics.advanceWidth("Failed"),
                ...root.entries.map(e => detailMetrics.advanceWidth(root.detailOf(e))))

            function moveSelection(step: int): void {
                if (list.count === 0)
                    return;
                root.selIndex = root.selIndex < 0
                    ? (step > 0 ? 0 : list.count - 1)
                    : Math.max(0, Math.min(list.count - 1, root.selIndex + step));
                list.positionViewAtIndex(root.selIndex, ListView.Contain);
            }

            // Password box closed (cancelled or submitted): typing goes to search again.
            Connections {
                target: root
                function onPskNetworkChanged(): void {
                    if (root.pskNetwork === null) {
                        searchField.text = "";
                        searchField.forceActiveFocus();
                    }
                }
            }

            function activateSelected(): void {
                const e = root.entries[root.selIndex];
                if (!e)
                    return;
                root.activateEntry(e);
                // Back to the full list so the result (border / "…") is visible,
                // unless the menu closed or now asks for a password.
                if (root.open && root.pskNetwork === null)
                    searchField.text = "";
            }

            Rectangle {
                id: frame

                anchors.fill: parent
                color: root.bgColor
                radius: 14
                border.width: 1
                border.color: root.borderColor

                ColumnLayout {
                    id: content

                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // Header: title | search | rescan | Wi-Fi switch
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        spacing: 8

                        Text {
                            text: "Wi-Fi"
                            color: root.textColor
                            font.family: root.fontFamily
                            font.pointSize: root.fontSize + 1
                            font.bold: true
                        }

                        // Search: focused on open, so typing goes straight here.
                        TextField {
                            id: searchField

                            Layout.fillWidth: true
                            implicitHeight: 28
                            color: root.textColor
                            placeholderText: Networking.wifiHardwareEnabled ? "Type to search…" : "Hardware switch off"
                            placeholderTextColor: root.dimTextColor
                            font.family: root.fontFamily
                            font.pointSize: root.fontSize - 1
                            leftPadding: 8
                            rightPadding: 8
                            selectByMouse: true
                            background: Rectangle {
                                radius: 8
                                color: root.fieldColor
                                border.width: 1
                                border.color: searchField.text !== "" ? root.activeBorderColor : root.borderColor
                            }

                            Component.onCompleted: forceActiveFocus()
                            onTextChanged: root.query = text.trim().toLowerCase()

                            // Escape always closes the menu, wherever the focus is.
                            Keys.onEscapePressed: root.close()
                            Keys.onUpPressed: win.moveSelection(-1)
                            Keys.onDownPressed: win.moveSelection(1)
                            Keys.onTabPressed: win.moveSelection(1)
                            Keys.onBacktabPressed: win.moveSelection(-1)
                            onAccepted: win.activateSelected()
                        }

                        // Rescan button
                        Rectangle {
                            id: refreshBtn

                            readonly property bool usable: root.wifiDevice !== null && Networking.wifiEnabled
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: 13
                            color: refreshMouse.containsMouse && usable ? root.hoverColor : "transparent"
                            opacity: usable ? 1 : 0.4

                            Text {
                                id: refreshIcon
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: root.rescanning ? root.activeBorderColor : root.textColor
                                font.family: root.iconFontFamily
                                font.pointSize: root.fontSize + 4

                                RotationAnimation on rotation {
                                    running: root.rescanning
                                    from: 0
                                    to: 360
                                    duration: 900
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) refreshIcon.rotation = 0
                                }
                            }

                            MouseArea {
                                id: refreshMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: refreshBtn.usable
                                onClicked: root.rescan()
                            }
                        }

                        Rectangle {
                            id: wifiSwitch

                            // Left click: Wi-Fi on/off. Right click: all networking on/off
                            // (red border while off; a left click then turns it back on).
                            readonly property bool on: Networking.wifiEnabled && root.networkingEnabled
                            implicitWidth: 40
                            implicitHeight: 22
                            radius: 11
                            color: on ? root.activeBorderColor : root.fieldColor
                            border.width: root.networkingEnabled ? 1 : 2
                            border.color: root.networkingEnabled ? root.borderColor : root.errorColor
                            opacity: Networking.wifiHardwareEnabled || !root.networkingEnabled ? 1 : 0.5

                            Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                y: 3
                                x: wifiSwitch.on ? parent.width - width - 3 : 3
                                color: wifiSwitch.on ? root.bgColor : root.dimTextColor
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton || !root.networkingEnabled)
                                        root.toggleNetworking();
                                    else if (Networking.wifiHardwareEnabled)
                                        Networking.wifiEnabled = !Networking.wifiEnabled;
                                }
                            }
                        }
                    }

                    // Status when there is nothing to list
                    Text {
                        visible: list.count === 0 || !root.networkingEnabled
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        Layout.bottomMargin: 6
                        horizontalAlignment: Text.AlignHCenter
                        text: !root.networkingEnabled ? "Networking is off (right-click the switch)"
                            : root.query !== "" ? "No matches"
                            : !root.wifiDevice ? "No Wi-Fi adapter"
                            : !Networking.wifiEnabled ? "Wi-Fi is off"
                            : "Scanning…"
                        color: root.networkingEnabled ? root.dimTextColor : root.errorColor
                        font.family: root.fontFamily
                        font.pointSize: root.fontSize
                    }

                    // Ethernet, VPN and Wi-Fi rows (or search results)
                    ListView {
                        id: list

                        readonly property bool overflowing: contentHeight > height + 1

                        visible: count > 0
                        Layout.fillWidth: true
                        implicitHeight: Math.min(contentHeight,
                            root.maxVisibleRows * (root.rowHeight + spacing) - spacing)
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.entries

                        ScrollBar.vertical: ScrollBar {
                            id: scrollBar
                            policy: list.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            width: 6
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: scrollBar.pressed || scrollBar.hovered ? root.textColor : root.dimTextColor
                            }
                            background: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: root.fieldColor
                            }
                        }

                        delegate: Item {
                            id: entry

                            required property var modelData
                            required property int index
                            readonly property string kind: modelData.kind
                            // Divider above the first row of each group (not while searching).
                            readonly property bool divider: root.query === "" && index > 0
                                && root.entries[index - 1]?.kind !== kind

                            readonly property WifiNetwork net: kind === "wifi" ? modelData.net : null
                            readonly property var dev: kind === "wired" ? modelData.dev : null
                            readonly property var vpn: kind === "vpn" ? modelData.vpn : null

                            // Leave room for the scrollbar.
                            width: list.width - (list.overflowing ? 12 : 0)
                            readonly property bool qrShown: kind === "wifi" && root.qrName !== ""
                                && root.qrName === modelData.label
                            readonly property int qrSize: 180

                            // Password box open under this row.
                            readonly property bool pskShown: kind === "wifi" && root.pskNetwork !== null
                                && root.pskNetwork === modelData.net

                            implicitHeight: row.y + row.implicitHeight
                                + (qrShown ? qrBox.height + 8 : 0)
                                + (pskShown ? pskBox.height + 8 : 0)

                            // Scroll so the whole QR code / password box is visible.
                            // (A Timer, not Qt.callLater: it dies with the row, which the list
                            // rebuilds as signal strengths change.)
                            onQrShownChanged: if (qrShown) qrScroll.restart()
                            onPskShownChanged: if (pskShown) pskBox.focusField()
                            // Opening the box freezes the list, which can recreate this row.
                            Component.onCompleted: if (pskShown) pskBox.focusField()

                            Timer {
                                id: qrScroll
                                interval: 0
                                onTriggered: entry.ListView.view?.positionViewAtIndex(entry.index, ListView.Contain)
                            }

                            Rectangle {
                                visible: entry.divider
                                y: 3
                                width: parent.width
                                height: 1
                                color: root.borderColor
                            }

                            NetRow {
                                id: row

                                y: entry.divider ? 9 : 0
                                width: parent.width
                                icon: entry.kind === "action" ? entry.modelData.icon
                                    : entry.kind === "wired" ? "󰈀"
                                    : entry.kind === "vpn" ? "󰖂"
                                    : root.signalIcon(entry.net?.signalStrength ?? 0)
                                label: entry.modelData.label
                                detail: entry.kind === "wired" ? root.wiredDetail(entry.dev)
                                    : entry.kind === "vpn" ? root.vpnDetail(entry.vpn)
                                    : entry.kind === "wifi" ? root.securityLabel(entry.net)
                                    : ""
                                detailWidth: win.detailWidth
                                connected: entry.kind === "wired" ? entry.dev.connected
                                    : entry.kind === "vpn" ? entry.vpn.state === "activated"
                                    : entry.kind === "wifi" ? (entry.net?.connected ?? false)
                                    : false
                                busy: entry.kind === "wired" ? (entry.dev.network?.stateChanging ?? false)
                                    : entry.kind === "vpn" ? root.vpnBusy === entry.vpn.uuid
                                    : entry.kind === "wifi" ? (entry.net?.stateChanging ?? false)
                                    : false
                                failed: root.failed[entry.modelData.key] === true
                                usable: entry.kind !== "wired" || (entry.dev.hasLink && entry.dev.network !== null)
                                selected: root.selIndex === entry.index
                                canForget: entry.net?.known ?? false
                                canReveal: entry.net?.known ?? false
                                revealed: entry.kind === "wifi" && root.revealName !== ""
                                    && root.revealName === entry.modelData.label
                                revealText: root.revealPassword
                                qrShown: entry.qrShown
                                onRevealToggled: root.toggleReveal(entry.modelData.label)
                                onQrToggled: root.toggleQr(entry.modelData.label)
                                onHovered: root.selIndex = entry.index
                                onActivated: root.activateEntry(entry.modelData)
                                forgetArmed: entry.kind === "wifi" && root.forgetArmed !== ""
                                    && root.forgetArmed === entry.modelData.label
                                onForgetRequested: root.requestForget(entry.net)
                            }

                            // QR code panel under the row (pushes the rows below down).
                            Rectangle {
                                id: qrBox

                                visible: entry.qrShown
                                y: row.y + row.height + 8
                                anchors.horizontalCenter: parent.horizontalCenter
                                // ~4 white modules around the code (quiet zone) for reliable scans.
                                width: entry.qrSize + 40
                                height: entry.qrSize + 40
                                radius: 12
                                color: "white"

                                Canvas {
                                    id: qrCanvas

                                    readonly property var rows: entry.qrShown ? root.qrRows : []
                                    anchors.centerIn: parent
                                    width: entry.qrSize
                                    height: entry.qrSize
                                    onRowsChanged: requestPaint()

                                    onPaint: {
                                        const ctx = getContext("2d");
                                        ctx.reset();
                                        const n = rows.length;
                                        if (n === 0)
                                            return;
                                        // Whole pixels per module, centred: crisp edges.
                                        const cell = Math.floor(width / n);
                                        const off = Math.floor((width - cell * n) / 2);
                                        ctx.fillStyle = "black";
                                        for (let y = 0; y < n; y++)
                                            for (let x = 0; x < n; x++)
                                                if (rows[y][x] === "1")
                                                    ctx.fillRect(off + x * cell, off + y * cell, cell, cell);
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - 24
                                    visible: root.qrRows.length === 0
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    text: root.qrError !== "" ? root.qrError : "…"
                                    color: root.qrError !== "" ? root.errorColor : "black"
                                    font.family: root.fontFamily
                                    font.pointSize: root.fontSize - 1
                                }
                            }

                            // Password box (secured network without a saved profile), under
                            // the row and aligned with the network name.
                            ColumnLayout {
                                id: pskBox

                                function focusField(): void {
                                    pskField.text = "";
                                    pskField.forceActiveFocus();
                                    qrScroll.restart();
                                }

                                visible: entry.pskShown
                                // Eye (26 px) centred under the Wi-Fi icon (row x 10..32), so the
                                // field starts at x 42, the name column.
                                x: 8
                                y: row.y + row.height + 8 + (entry.qrShown ? qrBox.height + 8 : 0)
                                width: parent.width - x - 4
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Show/hide, directly under the row's Wi-Fi icon.
                                    FooterButton {
                                        Layout.preferredWidth: 26
                                        implicitHeight: 30
                                        text: pskField.reveal ? "󰈈" : "󰈉"
                                        family: root.iconFontFamily
                                        pointSize: root.fontSize + 2
                                        onClicked: pskField.reveal = !pskField.reveal
                                    }

                                    // Starts under the network name, fills the rest.
                                    TextField {
                                        id: pskField

                                        property bool reveal: false
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        echoMode: reveal ? TextInput.Normal : TextInput.Password
                                        color: root.textColor
                                        placeholderText: "Password"
                                        placeholderTextColor: root.dimTextColor
                                        font.family: root.fontFamily
                                        font.pointSize: root.fontSize
                                        leftPadding: 10
                                        background: Rectangle {
                                            radius: 8
                                            color: root.fieldColor
                                            border.width: 1
                                            border.color: pskField.activeFocus ? root.activeBorderColor : root.borderColor
                                        }
                                        Keys.onEscapePressed: root.close()
                                        onAccepted: root.submitPsk(text)
                                    }

                                    FooterButton {
                                        implicitHeight: 30
                                        text: "Connect"
                                        onClicked: root.submitPsk(pskField.text)
                                    }
                                }

                                Text {
                                    visible: root.pskError !== ""
                                    Layout.leftMargin: 38
                                    text: root.pskError
                                    color: root.errorColor
                                    font.family: root.fontFamily
                                    font.pointSize: root.fontSize - 1
                                }
                            }

                            Connections {
                                target: entry.net
                                enabled: entry.net !== null
                                function onConnectionFailed(reason: int): void {
                                    root.setFailed(entry.modelData.key, true);
                                    // Wrong/missing password: ask again.
                                    if (reason === ConnectionFailReason.NoSecrets && root.isSecured(entry.net)) {
                                        root.askPassword(entry.net, "Wrong password, try again");
                                    }
                                }
                                function onConnectedChanged(): void {
                                    if (entry.net?.connected)
                                        root.setFailed(entry.modelData.key, false);
                                }
                            }
                        }
                    }

                    // Footer
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            text: root.query !== "" ? `${list.count} matches`
                                : root.wifiCount > 0 ? `${root.wifiCount} networks` : ""
                            color: root.dimTextColor
                            font.family: root.fontFamily
                            font.pointSize: root.fontSize - 1
                        }

                        FooterButton {
                            text: "More settings…"
                            onClicked: root.openSettings()
                        }
                    }
                }
            }
        }
    }
}
