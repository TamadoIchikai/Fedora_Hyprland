// Alt+Tab window switcher (Windows 11 style) for Hyprland.
//
// Based on Switcher.qml by ducduy9304, from
//   https://github.com/ducduy9304/hyprland-caelestia
//   (home/.config/caelestia/nix/switcher.patch, branch ubuntu-26.04)
// Adapted to run standalone (`qs -c altTab`) without the Caelestia shell, and
// trimmed for speed: opaque, no animations, one snapshot per window.
//
// Hyprland owns the keys (see ~/.config/hypr/hyprland.lua) and calls:
//   alttab:next / alttab:prev  open, or move the selection while open
//   alttab:commit              (ALT released) focus the selected window
//   alttab:cancel              close without switching
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    // Parking workspace (WM_PARK_WORKSPACE in ~/.config/abstractions/hyprland/workspace.sh).
    readonly property int parkWorkspace: 11
    // A quick ALT+Tab tap switches without showing the UI, like Windows 11.
    // Previews start capturing immediately (hidden), so this overlaps the capture time.
    readonly property int showDelayMs: 30
    // Show anyway after this long if some window can't be captured (its card shows the icon).
    readonly property int captureTimeoutMs: 100
    readonly property int previewWidth: 256
    readonly property int previewHeight: 144

    // Colours
    readonly property color bgColor: "#353535"
    readonly property color activeColor: "#5D5D5D"        // hovered / selected card
    readonly property color activeBorderColor: "#6A6F75"  // hovered / selected card border
    readonly property color previewBgColor: "#2B2B2B"
    readonly property color textColor: "#E6E6E6"
    readonly property color closeHoverColor: "#C42B1C"

    // Frozen while open, so the order doesn't jump around.
    property list<HyprlandToplevel> windows
    property int selected
    property bool open: false
    // Hidden UI is built on open so previews capture before it is shown.
    property bool delayElapsed: false
    property bool captureTimedOut: false
    property int capturedCount: 0
    // Latched: once visible, stays visible until closed.
    property bool shown: false
    readonly property bool readyToShow: open && delayElapsed
        && (captureTimedOut || capturedCount >= windows.length)
    onReadyToShowChanged: if (readyToShow) shown = true

    function recentWindows(): list<HyprlandToplevel> {
        const shown = Hyprland.toplevels.values.filter(t => {
            const ipc = t.lastIpcObject;
            // Skip special workspaces (negative id) and the parking workspace.
            return ipc?.mapped && !ipc.hidden && ipc.workspace?.id > 0
                && ipc.workspace.id !== root.parkWorkspace;
        });
        shown.sort((a, b) => a.lastIpcObject.focusHistoryID - b.lastIpcObject.focusHistoryID);
        return shown;
    }

    function step(direction: int): void {
        if (!open) {
            windows = recentWindows();
            if (windows.length === 0)
                return;
            // Start on the focused window, so the first step lands on the one used before it.
            // On an empty workspace nothing is focused, so the first step lands on the newest window.
            const focusedIsFirst = windows[0].lastIpcObject.workspace.id === Hyprland.focusedWorkspace?.id;
            selected = focusedIsFirst ? 0 : -direction;
            // Reset before `open`, so stale flags can't briefly satisfy readyToShow.
            delayElapsed = false;
            captureTimedOut = false;
            capturedCount = 0;
            shown = false;
            open = true;
            // Build the (invisible) UI right away so the snapshots start now.
            loader.active = true;
            showTimer.restart();
            captureTimer.restart();
        }
        const count = windows.length;
        selected = ((selected + direction) % count + count) % count;
    }

    function focusWindow(target: HyprlandToplevel): void {
        if (target)
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${target.address}" })`);
    }

    function commit(): void {
        if (!open)
            return;
        const target = windows[selected];
        close();
        focusWindow(target);
    }

    // × button: close that window and drop its card.
    function closeWindow(index: int): void {
        const target = windows[index];
        if (!target)
            return;
        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:0x${target.address}" })`);
        const remaining = windows.filter((_, i) => i !== index);
        if (remaining.length === 0) {
            close();
            return;
        }
        windows = remaining;
        selected = Math.min(selected, remaining.length - 1);
    }

    // Destroying the UI also frees every preview buffer.
    function close(): void {
        showTimer.stop();
        captureTimer.stop();
        loader.active = false;
        open = false;
        shown = false;
        windows = [];
    }

    Timer {
        id: showTimer
        interval: root.showDelayMs
        onTriggered: root.delayElapsed = true
    }

    Timer {
        id: captureTimer
        interval: root.captureTimeoutMs
        onTriggered: root.captureTimedOut = true
    }

    // Keep lastIpcObject (focus order, workspace, mapped) current. Only events
    // that change it: title changes (frequent in browsers/terminals) are ignored.
    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            switch (event.name) {
            case "activewindowv2":
            case "openwindow":
            case "closewindow":
            case "movewindowv2":
                Hyprland.refreshToplevels();
            }
        }
    }

    LazyLoader {
        id: loader

        PanelWindow {
            id: win

            readonly property int maxColumns: Math.max(1, Math.floor(screen.width * 0.9 / (root.previewWidth + 24)))

            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            color: "transparent"
            WlrLayershell.namespace: "alttab"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            // Hyprland binds drive the switcher, so it never takes the keyboard.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // While hidden (waiting for previews) let the mouse pass through.
            property Region hiddenMask: Region {}
            mask: root.shown ? null : hiddenMask

            // No anchors: the compositor centres it.
            implicitWidth: grid.implicitWidth + 32
            implicitHeight: grid.implicitHeight + 32

            Rectangle {
                anchors.fill: parent
                // opacity (not visible) so the previews still render while hidden.
                opacity: root.shown ? 1 : 0
                color: root.bgColor
                radius: 16
                border.width: 1
                border.color: root.activeColor

                GridLayout {
                    id: grid

                    anchors.centerIn: parent
                    columns: Math.max(1, Math.min(root.windows.length, win.maxColumns))
                    columnSpacing: 8
                    rowSpacing: 8

                    Repeater {
                        model: root.windows

                        Rectangle {
                            id: card

                            required property HyprlandToplevel modelData
                            required property int index
                            readonly property bool isSelected: index === root.selected
                            readonly property string icon: {
                                const cls = modelData.lastIpcObject.class ?? "";
                                return Quickshell.iconPath(DesktopEntries.heuristicLookup(cls)?.icon ?? cls, "application-x-executable");
                            }

                            implicitWidth: root.previewWidth + 16
                            implicitHeight: content.implicitHeight + 16
                            // Hovering selects, so hover and selection share one look.
                            color: isSelected ? root.activeColor : root.bgColor
                            radius: 12
                            border.width: 2
                            border.color: isSelected ? root.activeBorderColor : root.bgColor

                            // Hover selects, click focuses.
                            MouseArea {
                                id: mouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.shown
                                onEntered: root.selected = card.index
                                onClicked: {
                                    const target = card.modelData;
                                    root.close();
                                    root.focusWindow(target);
                                }
                            }

                            ColumnLayout {
                                id: content

                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                RowLayout {
                                    spacing: 8

                                    IconImage {
                                        implicitSize: 20
                                        source: card.icon
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: card.modelData.title
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        color: root.textColor
                                        font.pointSize: 11
                                    }

                                    // × close button, shown on the selected/hovered card.
                                    Rectangle {
                                        implicitWidth: 20
                                        implicitHeight: 20
                                        radius: 10
                                        visible: card.isSelected
                                        color: closeMouse.containsMouse ? root.closeHoverColor : root.activeColor

                                        Text {
                                            anchors.centerIn: parent
                                            text: "×"
                                            color: root.textColor
                                            font.pointSize: 11
                                        }

                                        MouseArea {
                                            id: closeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: root.closeWindow(card.index)
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: root.previewWidth
                                    Layout.preferredHeight: root.previewHeight
                                    color: root.previewBgColor
                                    radius: 8
                                    clip: true

                                    // Until the snapshot arrives, or if the window can't be captured.
                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitSize: 64
                                        source: card.icon
                                        visible: !preview.hasContent
                                    }

                                    // One GPU snapshot per window when the switcher opens:
                                    // no files, no encoding, freed on close.
                                    ScreencopyView {
                                        id: preview

                                        anchors.centerIn: parent
                                        captureSource: card.modelData.wayland
                                        live: false
                                        constraintSize.width: root.previewWidth
                                        constraintSize.height: root.previewHeight
                                        onHasContentChanged: if (hasContent) root.capturedCount++
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    GlobalShortcut {
        appid: "alttab"
        name: "next"
        onPressed: root.step(1)
    }

    GlobalShortcut {
        appid: "alttab"
        name: "prev"
        onPressed: root.step(-1)
    }

    GlobalShortcut {
        appid: "alttab"
        name: "commit"
        // Bound to the release of ALT; Hyprland may report either signal.
        onPressed: root.commit()
        onReleased: root.commit()
    }

    GlobalShortcut {
        appid: "alttab"
        name: "cancel"
        onPressed: root.close()
    }
}
