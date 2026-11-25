import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import QtQuick

// Top bar: launcher button, active app, clock, status and Control Center toggle.
PanelWindow {
    id: bar
    required property var shell

    anchors { top: true; left: true; right: true }
    implicitHeight: 52
    exclusiveZone: 48
    color: "transparent"
    WlrLayershell.namespace: "frost-bar"

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: bar.sink ? [bar.sink] : [] }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Glass {
        anchors { fill: parent; leftMargin: 10; rightMargin: 10; topMargin: 8; bottomMargin: 8 }
        radius: 14

        Row {
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
            spacing: 2
            IconButton { icon: "peak"; onClicked: bar.shell.toggleLauncher(false) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 8
                text: {
                    const t = ToplevelManager.activeToplevel
                    if (!t) return "Desktop"
                    const id = t.appId || ""
                    // Quickshell windows (e.g. the installer) all share one app id: use their title
                    if (id === "org.quickshell") return t.title || "Desktop"
                    const e = DesktopEntries.byId(id)
                    return e ? e.name : (t.title || id || "Desktop")
                }
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Bold
            }
        }

        Text {
            anchors.centerIn: parent
            text: Qt.formatDateTime(clock.date, "ddd d MMM   HH:mm")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Row {
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            spacing: 2
            IconButton {
                icon: "store"
                label: bar.shell.packageCount > 0 ? String(bar.shell.packageCount) : ""
                onClicked: bar.shell.toggleLauncher(true)
            }
            IconButton { icon: bar.shell.wifiOn ? "wifi" : "wifi-off"; onClicked: bar.shell.toggleControlCenter() }
            IconButton {
                visible: bar.sink !== null && bar.sink.audio !== null
                icon: (bar.sink && bar.sink.audio && !bar.sink.audio.muted) ? "volume" : "mute"
                label: (bar.sink && bar.sink.audio) ? Math.round(bar.sink.audio.volume * 100) + "%" : ""
                onClicked: bar.shell.toggleControlCenter()
            }
            IconButton {
                readonly property var dev: UPower.displayDevice
                visible: dev !== null && dev.isLaptopBattery
                icon: "battery"
                iconSize: 19
                // percentage is 0..1 in current Quickshell; accept 0..100 too.
                label: dev ? Math.round(dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage) + "%" : ""
                onClicked: bar.shell.toggleControlCenter()
            }
            IconButton { icon: "search"; onClicked: bar.shell.toggleLauncher(false) }
            IconButton { icon: "cc"; active: bar.shell.ccOpen; onClicked: bar.shell.toggleControlCenter() }
        }
    }
}
