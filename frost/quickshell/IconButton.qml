import QtQuick

// Small pill button with an SVG icon and optional label, used in the bar.
Rectangle {
    id: root
    property string icon: ""
    property string label: ""
    property bool active: false
    property int iconSize: 16
    property color hoverColor: Theme.hover
    signal clicked()

    implicitHeight: 28
    implicitWidth: row.implicitWidth + 20
    radius: 9
    color: (mouse.containsMouse || active) ? hoverColor : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Image {
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            source: root.icon !== "" ? Theme.icon(root.icon) : ""
            sourceSize.width: root.iconSize
            sourceSize.height: root.iconSize
        }
        Text {
            visible: root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
