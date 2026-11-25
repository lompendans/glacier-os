import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Controls

// Control Center: quick toggles, volume/brightness, power actions.
PanelWindow {
    id: win
    required property var shell

    visible: shell.ccOpen
    anchors { top: true; right: true }
    margins { top: 50; right: 10 }
    implicitWidth: 340
    implicitHeight: col.implicitHeight + 28
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "frost-cc"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: win.sink ? [win.sink] : [] }

    property bool btOn: false
    property bool dnd: false
    property int brightness: -1     // -1 = no backlight (desktop / VM)

    onVisibleChanged: if (visible) { btProc.running = true; dndProc.running = true; briProc.running = true }

    Process { id: btProc; command: ["bluetoothctl", "show"]
        stdout: StdioCollector { onStreamFinished: win.btOn = /Powered: yes/.test(text) } }
    Process { id: dndProc; command: ["makoctl", "mode"]
        stdout: StdioCollector { onStreamFinished: win.dnd = text.indexOf("do-not-disturb") !== -1 } }
    Process { id: briProc; command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector { onStreamFinished: {
            const f = text.trim().split(",")
            win.brightness = f.length >= 4 ? parseInt(f[3]) : -1
        } } }

    Glass {
        anchors.fill: parent
        radius: 24
        under: 0.4
        focus: true
        Keys.onEscapePressed: win.shell.ccOpen = false

        Column {
            id: col
            x: 14; y: 14
            width: parent.width - 28
            spacing: 10

            Grid {
                columns: 2
                spacing: 10
                Tile { name: "Wi-Fi"; glyph: "wifi"; on: win.shell.wifiOn; sub: on ? "On" : "Off"
                    onClicked: { Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "off" : "on"]); win.shell.wifiOn = !on } }
                Tile { name: "Bluetooth"; glyph: "bt"; on: win.btOn; sub: on ? "On" : "Off"
                    onClicked: { Quickshell.execDetached(["bluetoothctl", "power", on ? "off" : "on"]); win.btOn = !on } }
                Tile { name: "Focus"; glyph: "bell-off"; on: win.dnd; sub: on ? "Silenced" : "Off"
                    onClicked: { Quickshell.execDetached(["makoctl", "mode", "-t", "do-not-disturb"]); win.dnd = !on } }
                Tile { name: "Packages"; glyph: "store"; on: false; sub: win.shell.packageCount + " installed"
                    onClicked: { win.shell.ccOpen = false; win.shell.toggleLauncher(true) } }
            }

            SliderRow {
                visible: win.sink !== null && win.sink.audio !== null
                label: "Sound"; glyph: "volume"
                value: (win.sink && win.sink.audio) ? win.sink.audio.volume : 0
                onMoved: v => { if (win.sink && win.sink.audio) win.sink.audio.volume = v }
            }
            SliderRow {
                visible: win.brightness >= 0
                label: "Display"; glyph: "sun"
                value: Math.max(0, win.brightness) / 100
                onMoved: v => { const p = Math.max(5, Math.round(v * 100)); win.brightness = p
                                Quickshell.execDetached(["brightnessctl", "-c", "backlight", "set", p + "%"]) }
            }

            Row {
                spacing: 10
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: [
                        { g: "lock", cmd: ["loginctl", "lock-session"] },
                        { g: "logout", cmd: ["hyprctl", "dispatch", "exit"] },
                        { g: "reboot", cmd: ["systemctl", "reboot"] },
                        { g: "power", cmd: ["systemctl", "poweroff"] }
                    ]
                    Rectangle {
                        required property var modelData
                        width: 70; height: 44; radius: 14
                        color: pm.containsMouse ? Theme.hover : Theme.well
                        Image { anchors.centerIn: parent; source: Theme.icon(modelData.g); sourceSize.width: 18; sourceSize.height: 18 }
                        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true
                            onClicked: { win.shell.ccOpen = false; Quickshell.execDetached(modelData.cmd) } }
                    }
                }
            }
        }
    }

    component Tile: Rectangle {
        id: t
        property string name
        property string sub
        property string glyph
        property bool on
        signal clicked()
        width: (col.width - 10) / 2
        height: 58
        radius: 18
        color: tm.containsMouse ? Theme.hover : Theme.well
        Row {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 10
            Rectangle {
                width: 32; height: 32; radius: 16
                color: t.on ? Theme.accent : Theme.hover
                Behavior on color { ColorAnimation { duration: 150 } }
                Image { anchors.centerIn: parent; source: Theme.icon(t.glyph); sourceSize.width: 16; sourceSize.height: 16 }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: t.name; color: Theme.fg; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { text: t.sub; color: Theme.fg3; font.family: Theme.font; font.pixelSize: 11 }
            }
        }
        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; onClicked: t.clicked() }
    }

    component SliderRow: Rectangle {
        id: s
        property string label
        property string glyph
        property real value
        signal moved(real v)
        width: col.width
        height: 74
        radius: 18
        color: Theme.well

        // label on top, then [icon  slider] on one line, everything with explicit sizes
        // (the Basic style's implicit slider height/padding pushed the track into the label)
        Text {
            x: 16; y: 12
            text: s.label
            color: Theme.fg; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        }
        Item {
            x: 16; y: 38
            width: parent.width - 32
            height: 22
            Image {
                id: glyphIcon
                anchors.verticalCenter: parent.verticalCenter
                source: Theme.icon(s.glyph)
                sourceSize.width: 16; sourceSize.height: 16
            }
            Slider {
                id: sl
                anchors { left: glyphIcon.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 22
                padding: 0
                from: 0; to: 1
                value: s.value
                onMoved: s.moved(value)
                background: Rectangle {
                    width: sl.width; height: sl.height; radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.15)
                    Rectangle {
                        width: Math.max(parent.height, sl.handle.x + sl.handle.width)
                        height: parent.height; radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.85)
                    }
                }
                handle: Rectangle {
                    x: sl.visualPosition * (sl.width - width)
                    y: 0
                    width: 22; height: 22; radius: 11
                    color: "white"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.12)
                }
            }
        }
    }
}
