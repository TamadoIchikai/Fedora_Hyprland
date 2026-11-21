// Wi-Fi menu (replaces the fuzzel `networkmanager_dmenu`, which stays as a fallback).
//
// Opened from the waybar network module:
//   qs -c quickshell_modules ipc call wifi toggle      (also: open / close)
//
// Uses Quickshell.Networking (NetworkManager over D-Bus), no nmcli calls.
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
    readonly property int rowHeight: 36
    readonly property int maxVisibleRows: 10
    // Centres the menu on the waybar Wi-Fi icon (icon centre is 256 px from the
    // right screen edge; 256 - menuWidth / 2).
    readonly property int marginRight: 56
    readonly property int marginBottom: 8

    property bool open: false
    // Network waiting for a password (null = password box hidden).
    property WifiNetwork pskNetwork: null
    property string pskError: ""
    // A click on the waybar icon first clears the focus grab (closing the menu)
    // and then runs `toggle`; don't reopen right away in that case.
    property double grabClosedAt: 0

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

    function show(): void {
        pskNetwork = null;
        pskError = "";
        open = true;
    }

    function close(): void {
        open = false;
        pskNetwork = null;
        pskError = "";
    }

    function toggle(): void {
        if (open)
            close();
        else if (Date.now() - grabClosedAt > 400)
            show();
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

    function activate(n: WifiNetwork): void {
        if (!n || n.stateChanging)
            return;
        if (n.connected) {
            n.disconnect();
        } else if (n.known || !isSecured(n)) {
            n.connect();
        } else {
            pskError = isEnterprise(n) ? "Enterprise network: use More settings" : "";
            pskNetwork = n;
        }
    }

    function submitPsk(psk: string): void {
        if (!pskNetwork || psk.length === 0)
            return;
        pskNetwork.connectWithPsk(psk);
        pskNetwork = null;
        pskError = "";
    }

    IpcHandler {
        target: "wifi"

        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
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
        signal activated()
        signal forgetRequested()
        signal hovered()

        implicitHeight: root.rowHeight
        radius: 8
        color: selected && usable ? root.hoverColor : "transparent"
        border.width: 2
        border.color: connected ? root.activeBorderColor : "transparent"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.usable
            onEntered: row.hovered()
            onClicked: row.activated()
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

            Text {
                Layout.fillWidth: true
                text: row.label
                elide: Text.ElideRight
                maximumLineCount: 1
                color: row.usable ? root.textColor : root.dimTextColor
                font.family: root.fontFamily
                font.pointSize: root.fontSize
                font.bold: row.connected
            }

            Text {
                Layout.preferredWidth: row.detailWidth > 0 ? row.detailWidth : implicitWidth
                horizontalAlignment: Text.AlignRight
                text: row.busy ? "…" : row.failed ? "Failed" : row.detail
                color: row.failed ? root.errorColor : root.dimTextColor
                font.family: root.fontFamily
                font.pointSize: root.fontSize - 1
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
                    color: trashMouse.containsMouse ? root.errorColor : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰆴"
                        color: row.selected || trashMouse.containsMouse ? root.textColor : root.dimTextColor
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
            font.family: root.fontFamily
            font.pointSize: root.fontSize - 1
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
            anchors.bottom: true
            anchors.right: true
            margins.right: root.marginRight
            margins.bottom: root.marginBottom
            color: "transparent"
            WlrLayershell.namespace: "wifi"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            implicitWidth: root.menuWidth
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

            // Width of the security column: fits the longest label shown (no empty space).
            readonly property real secWidth: Math.max(detailMetrics.advanceWidth("Failed"),
                ...root.networks.map(n => detailMetrics.advanceWidth(root.securityLabel(n))))

            Rectangle {
                id: frame

                anchors.fill: parent
                color: root.bgColor
                radius: 14
                border.width: 1
                border.color: root.borderColor
                focus: true

                Keys.onEscapePressed: root.close()
                Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
                Keys.onDownPressed: list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1)
                Keys.onReturnPressed: root.activate(root.networks[list.currentIndex] ?? null)
                Keys.onEnterPressed: root.activate(root.networks[list.currentIndex] ?? null)

                ColumnLayout {
                    id: content

                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // Header: title + Wi-Fi switch
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4

                        Text {
                            Layout.fillWidth: true
                            text: "Wi-Fi"
                            color: root.textColor
                            font.family: root.fontFamily
                            font.pointSize: root.fontSize + 1
                            font.bold: true
                        }

                        Text {
                            visible: !Networking.wifiHardwareEnabled
                            text: "Hardware switch off"
                            color: root.dimTextColor
                            font.family: root.fontFamily
                            font.pointSize: root.fontSize - 1
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

                            readonly property bool on: Networking.wifiEnabled
                            implicitWidth: 40
                            implicitHeight: 22
                            radius: 11
                            color: on ? root.activeBorderColor : root.fieldColor
                            border.width: 1
                            border.color: root.borderColor
                            opacity: Networking.wifiHardwareEnabled ? 1 : 0.5

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
                                enabled: Networking.wifiHardwareEnabled
                                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                            }
                        }
                    }

                    // Wired devices
                    Repeater {
                        model: root.wiredDevices

                        NetRow {
                            id: wiredRow

                            required property WiredDevice modelData
                            readonly property Network net: modelData.network

                            Layout.fillWidth: true
                            icon: "󰈀"
                            label: `Ethernet (${modelData.name})`
                            detail: !modelData.hasLink ? "Unplugged"
                                : modelData.connected ? `${modelData.linkSpeed} Mb/s`
                                : "Disconnected"
                            connected: modelData.connected
                            busy: net?.stateChanging ?? false
                            usable: modelData.hasLink && net !== null
                            selected: hoverArea.containsMouse
                            onActivated: {
                                if (!net || net.stateChanging)
                                    return;
                                if (net.connected)
                                    net.disconnect();
                                else
                                    net.connect();
                            }

                            MouseArea {
                                id: hoverArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }
                    }

                    Rectangle {
                        visible: root.wiredDevices.length > 0
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: root.borderColor
                    }

                    // Status when there is nothing to list
                    Text {
                        visible: list.count === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        Layout.bottomMargin: 6
                        horizontalAlignment: Text.AlignHCenter
                        text: !root.wifiDevice ? "No Wi-Fi adapter"
                            : !Networking.wifiEnabled ? "Wi-Fi is off"
                            : "Scanning…"
                        color: root.dimTextColor
                        font.family: root.fontFamily
                        font.pointSize: root.fontSize
                    }

                    // Wi-Fi networks
                    ListView {
                        id: list

                        readonly property bool overflowing: contentHeight > height + 1

                        visible: count > 0
                        Layout.fillWidth: true
                        implicitHeight: Math.min(contentHeight,
                            root.maxVisibleRows * (root.rowHeight + spacing) - spacing)
                        clip: true
                        spacing: 2
                        currentIndex: -1
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.networks

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

                        delegate: NetRow {
                            id: wifiRow

                            required property WifiNetwork modelData
                            required property int index
                            property bool lastFailed: false

                            // Leave room for the scrollbar.
                            width: list.width - (list.overflowing ? 12 : 0)
                            icon: root.signalIcon(modelData?.signalStrength ?? 0)
                            label: modelData?.name ?? ""
                            detail: root.securityLabel(modelData)
                            detailWidth: win.secWidth
                            connected: modelData?.connected ?? false
                            busy: modelData?.stateChanging ?? false
                            failed: lastFailed
                            selected: list.currentIndex === index
                            canForget: modelData?.known ?? false
                            onHovered: list.currentIndex = index
                            onActivated: {
                                lastFailed = false;
                                root.activate(modelData);
                            }
                            onForgetRequested: modelData?.forget()

                            Connections {
                                target: wifiRow.modelData
                                function onConnectionFailed(reason: int): void {
                                    wifiRow.lastFailed = true;
                                    // Wrong/missing password: ask again.
                                    if (reason === ConnectionFailReason.NoSecrets && root.isSecured(wifiRow.modelData)) {
                                        root.pskError = "Wrong password, try again";
                                        root.pskNetwork = wifiRow.modelData;
                                    }
                                }
                                function onConnectedChanged(): void {
                                    if (wifiRow.modelData?.connected)
                                        wifiRow.lastFailed = false;
                                }
                            }
                        }
                    }

                    // Password box (secured network without a saved profile)
                    ColumnLayout {
                        visible: root.pskNetwork !== null
                        Layout.fillWidth: true
                        spacing: 6

                        onVisibleChanged: if (visible) {
                            pskField.text = "";
                            pskField.forceActiveFocus();
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            text: `Password for ${root.pskNetwork?.name ?? ""}`
                            elide: Text.ElideRight
                            color: root.textColor
                            font.family: root.fontFamily
                            font.pointSize: root.fontSize - 1
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            TextField {
                                id: pskField

                                property bool reveal: false
                                Layout.fillWidth: true
                                implicitHeight: 32
                                echoMode: reveal ? TextInput.Normal : TextInput.Password
                                color: root.textColor
                                placeholderText: "Passphrase"
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
                                Keys.onEscapePressed: {
                                    root.pskNetwork = null;
                                    frame.forceActiveFocus();
                                }
                                onAccepted: {
                                    root.submitPsk(text);
                                    frame.forceActiveFocus();
                                }
                            }

                            FooterButton {
                                text: pskField.reveal ? "󰈉" : "󰈈"
                                onClicked: pskField.reveal = !pskField.reveal
                            }

                            FooterButton {
                                text: "Connect"
                                onClicked: {
                                    root.submitPsk(pskField.text);
                                    frame.forceActiveFocus();
                                }
                            }
                        }

                        Text {
                            visible: root.pskError !== ""
                            Layout.leftMargin: 4
                            text: root.pskError
                            color: root.errorColor
                            font.family: root.fontFamily
                            font.pointSize: root.fontSize - 1
                        }
                    }

                    // Footer
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            text: list.count > 0 ? `${list.count} networks` : ""
                            color: root.dimTextColor
                            font.family: root.fontFamily
                            font.pointSize: root.fontSize - 1
                        }

                        FooterButton {
                            text: "More settings…"
                            onClicked: {
                                Quickshell.execDetached(["nm-connection-editor"]);
                                root.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
