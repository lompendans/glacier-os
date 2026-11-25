import QtQuick

// Liquid-glass surface. The compositor (Hyprland layer rules) blurs what is behind
// the layer; this item adds the tint, the refractive rim and the specular highlight.
Item {
    id: root
    property real radius: 18
    property real tint: Theme.tint
    property real under: 0          // extra dark underlay for readability (0..1)
    default property alias content: inner.data

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.rgba(0.055, 0.07, 0.14, root.under)
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.tint * 1.25) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, root.tint * 0.45) }
        }
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.30)
    }
    // specular highlight along the top edge
    Rectangle {
        x: root.radius * 0.6
        y: 1
        width: parent.width - root.radius * 1.2
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, 0.75) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.15) }
        }
    }
    Item {
        id: inner
        anchors.fill: parent
    }
}
