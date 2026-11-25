pragma Singleton
import Quickshell
import QtQuick

// Frost design tokens — mirror the values used in the concept UI.
Singleton {
    readonly property color accent: "#5ac8fa"
    readonly property real tint: 0.16
    readonly property color fg: "#ffffff"
    readonly property color fg2: Qt.rgba(1, 1, 1, 0.74)
    readonly property color fg3: Qt.rgba(1, 1, 1, 0.5)
    readonly property color hover: Qt.rgba(1, 1, 1, 0.14)
    readonly property color well: Qt.rgba(0, 0, 0, 0.18)
    readonly property string font: "Inter"
    readonly property string mono: "JetBrains Mono"

    function icon(name) { return Qt.resolvedUrl("icons/" + name + ".svg") }

    // Apps pinned to the dock: desktop-entry id + fallback command.
    readonly property var pinned: [
        { id: "thunar", name: "Files", icon: "org.xfce.thunar", cmd: ["thunar"] },
        { id: "firefox", name: "Web", icon: "firefox", cmd: ["firefox"] },
        { id: "foot", name: "Terminal", icon: "foot", cmd: ["foot"] },
        { id: "pavucontrol", name: "Sound", icon: "multimedia-volume-control", cmd: ["pavucontrol"] }
    ]
}
