// Drag-and-drop zone shown to the LEFT of the LocalSend file picker (right click
// on the waybar share icon -> ~/.local/bin/localsend-send.sh --pick).
// Drop files (e.g. from Thunar on the same workspace): each drop goes straight
// into LocalSend's Send selection (`localsend-send.sh --add`). "Done" closes the
// picker; the script then shows LocalSend.
//
// The script drives it over IPC:
//   qs -c quickshell_modules ipc call dropzone open <picker-pid>
//   qs -c quickshell_modules ipc call dropzone close     -> prints files added
// Placement uses the same monitor fractions as the picker's window rule in
// ~/.config/hypr/hyprland.lua ("Send with LocalSend"): keep them in sync.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // Colours (shared with Wifi.qml)
    readonly property color bgColor: "#353535"
    readonly property color hoverColor: "#5D5D5D"
    readonly property color borderColor: "#5D5D5D"
    readonly property color accentColor: "#FFCB66"
    readonly property color textColor: "#E6E6E6"
    readonly property color dimTextColor: "#8F8F8F"
    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"
    readonly property string iconFontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 11

    // Picker rule (hyprland.lua): move monitor_w*0.5682, monitor_h*0.4509,
    // size monitor_w*0.4281 x monitor_h*0.5139. The zone sits left of it.
    readonly property real pickerX: 0.5682
    readonly property real pickerY: 0.4509
    readonly property real pickerH: 0.5139
    readonly property real zoneW: 0.15
    readonly property int gap: 8

    readonly property string sendScript: `${Quickshell.env("HOME")}/.local/bin/localsend-send.sh`

    // Requested by the script (between `open` and `close`)...
    property bool open: false
    // ...but only drawn while the picker window itself is on screen, so both
    // appear and disappear together. Keyed to Hyprland's openwindow /
    // closewindow events: the portal sets the title ~70 ms before the window
    // actually maps, so matching on the title alone shows the zone too early.
    readonly property string pickerTitle: "Send with LocalSend"
    property string pickerAddress: ""
    readonly property bool pickerShown: pickerAddress !== ""

    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "openwindow") {
                // data: address,workspace,class,title (title may contain commas)
                const parts = event.data.split(",");
                if (parts.slice(3).join(",") === root.pickerTitle)
                    root.pickerAddress = parts[0];
            } else if (event.name === "closewindow" && event.data === root.pickerAddress) {
                root.pickerAddress = "";
            }
        }
    }
    // zenity of the running picker: "Done" ends it.
    property string pickerPid: ""
    // Files added by drops, and the newest names (shown in the zone).
    property int added: 0
    property var names: []

    // file:// URLs -> local paths -> LocalSend Send selection.
    function addUrls(urls: var): void {
        const paths = Array.from(urls)
            .map(u => String(u))
            .filter(u => u.startsWith("file://"))
            .map(u => decodeURIComponent(u.slice("file://".length)));
        if (paths.length === 0)
            return;
        Quickshell.execDetached([sendScript, "--add", ...paths]);
        added += paths.length;
        names = [...paths.map(p => p.replace(/\/$/, "").split("/").pop()), ...names].slice(0, 8);
    }

    function done(): void {
        if (/^[0-9]+$/.test(pickerPid))
            Quickshell.execDetached(["kill", pickerPid]);
    }

    IpcHandler {
        target: "dropzone"

        function open(pid: string): void {
            root.pickerPid = pid;
            root.pickerAddress = "";
            root.added = 0;
            root.names = [];
            root.open = true;
        }

        // Returns how many files were dropped.
        function close(): string {
            root.open = false;
            return String(root.added);
        }
    }

    // Built and mapped (invisible, click-through) as soon as the picker is
    // requested; when the picker window appears only the content's opacity
    // changes: one redraw instead of creating a surface (~40 ms later).
    LazyLoader {
        active: root.open

        PanelWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            anchors.top: true
            anchors.left: true
            implicitWidth: Math.round(screen.width * root.zoneW)
            implicitHeight: Math.round(screen.height * root.pickerH)
            // Right edge `gap` px left of the picker, same top and height.
            margins.left: Math.round(screen.width * root.pickerX) - root.gap - implicitWidth
            margins.top: Math.round(screen.height * root.pickerY)
            color: "transparent"
            WlrLayershell.namespace: "localsend-drop"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // No input (clicks, drops) while invisible.
            mask: root.pickerShown ? null : noInput
            Region { id: noInput }

            Rectangle {
                id: frame

                anchors.fill: parent
                opacity: root.pickerShown ? 1 : 0
                radius: 12
                color: root.bgColor
                border.width: 1
                border.color: root.borderColor

                // Dashed drop target, highlighted while something is dragged over it.
                Shape {
                    id: target

                    anchors.fill: parent
                    anchors.margins: 10
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: drop.containsDrag ? root.accentColor : root.dimTextColor
                        strokeWidth: 2
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [4, 3]
                        fillColor: drop.containsDrag ? Qt.rgba(1, 0.8, 0.4, 0.08) : "transparent"

                        PathRectangle {
                            x: 1
                            y: 1
                            width: target.width - 2
                            height: target.height - 2
                            radius: 10
                        }
                    }
                }

                DropArea {
                    id: drop

                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onEntered: drag => drag.accept(Qt.CopyAction)
                    onDropped: dropEvent => {
                        root.addUrls(dropEvent.urls);
                        dropEvent.accept(Qt.CopyAction);
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 10

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.added > 0 ? "󰄬" : "󰮏"
                        color: drop.containsDrag || root.added > 0 ? root.accentColor : root.textColor
                        font.family: root.iconFontFamily
                        font.pointSize: 34
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: drop.containsDrag ? "Release to add"
                            : root.added > 0 ? `${root.added} file${root.added > 1 ? "s" : ""} added`
                            : "Drop files here"
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pointSize: root.fontSize + 1
                        font.bold: true
                    }

                    Text {
                        visible: root.added === 0
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "They go straight to LocalSend"
                        color: root.dimTextColor
                        font.family: root.fontFamily
                        font.pointSize: root.fontSize - 1
                    }

                    // Newest dropped names.
                    Repeater {
                        model: root.names

                        Text {
                            required property string modelData
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            elide: Text.ElideMiddle
                            color: root.dimTextColor
                            font.family: root.fontFamily
                            font.pointSize: root.fontSize - 1
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Closes the picker; LocalSend then comes to this workspace.
                    Rectangle {
                        visible: root.added > 0
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: doneText.implicitWidth + 32
                        implicitHeight: 30
                        radius: 8
                        color: doneMouse.containsMouse ? root.accentColor : root.hoverColor

                        Text {
                            id: doneText
                            anchors.centerIn: parent
                            text: "Done"
                            color: doneMouse.containsMouse ? root.bgColor : root.textColor
                            font.family: root.fontFamily
                            font.pointSize: root.fontSize
                            font.bold: true
                        }

                        MouseArea {
                            id: doneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.done()
                        }
                    }
                }
            }
        }
    }
}
