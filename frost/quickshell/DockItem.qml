import Quickshell
import QtQuick

// One dock icon. Its slot never changes size (so neighbours never move); only the picture
// is scaled, from the bottom edge, by `magnify` (set by the dock from the pointer position).
Item {
    id: root
    property string label: ""
    property string iconName: ""
    property string glyph: ""
    property bool running: false
    property real magnify: 1.0
    property real shift: 0          // sideways offset so magnified neighbours don't overlap
    signal clicked()

    width: 52
    height: 52
    transform: Translate { x: root.shift }

    // press feedback (the magnification itself is already smooth: it follows the pointer)
    property real press: tap.pressed ? 0.92 : 1.0
    Behavior on press { NumberAnimation { duration: 90 } }

    Item {
        id: visual
        anchors.fill: parent
        transformOrigin: Item.Bottom
        scale: root.magnify * root.press

        // glyph tile (launcher / packages)
        Rectangle {
            visible: root.glyph !== ""
            anchors.fill: parent
            radius: width * 0.28
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#8a7dff" }
                GradientStop { position: 1.0; color: "#c06bff" }
            }
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.35)
            Image {
                anchors.centerIn: parent
                source: root.glyph !== "" ? Theme.icon(root.glyph) : ""
                sourceSize.width: 52
                sourceSize.height: 52
                width: parent.width * 0.5
                height: parent.height * 0.5
            }
        }
        Image {
            visible: root.iconName !== ""
            anchors.fill: parent
            source: root.iconName !== "" ? Quickshell.iconPath(root.iconName, "application-x-executable") : ""
            sourceSize.width: 128
            sourceSize.height: 128
            smooth: true
        }
    }

    // running indicator (not scaled)
    Rectangle {
        anchors { top: parent.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter }
        width: 5; height: 5; radius: 2.5
        color: Theme.fg
        opacity: root.running ? 0.9 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // name label: always sits just above the (scaled) icon, at its normal size
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: -root.height * (visual.scale - 1) - height - 8
        width: tip.implicitWidth + 20
        height: 26
        radius: 10
        color: Qt.rgba(0.08, 0.1, 0.2, 0.85)
        border.color: Qt.rgba(1, 1, 1, 0.25)
        opacity: hover.hovered ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Text {
            id: tip
            anchors.centerIn: parent
            text: root.label
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    HoverHandler { id: hover }
    TapHandler {
        id: tap
        onTapped: root.clicked()
    }
}
