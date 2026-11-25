import Quickshell
import Quickshell.Wayland
import QtQuick

// Bottom dock with pointer-following magnification.
// Icons keep fixed slots in the Row (it never re-lays out). Their pictures scale up from the
// bottom, and each icon is shifted sideways by the growth of the icons before it, so magnified
// icons push their neighbours apart instead of overlapping; the glass widens to match.
PanelWindow {
    id: dock
    required property var shell

    readonly property real iconSize: 52
    readonly property real maxMagnify: 1.36       // icon under the pointer: 52 px -> ~71 px
    readonly property real reach: 140             // px from the pointer where magnification fades out

    anchors.bottom: true
    implicitWidth: row.implicitWidth + 220        // constant: headroom for the wider, magnified dock
    implicitHeight: 168                           // headroom for magnified icons + name labels
    exclusiveZone: 86
    color: "transparent"
    WlrLayershell.namespace: "frost-dock"
    // only the dock itself (plus the strip a magnified icon reaches into) takes input,
    // so the transparent headroom never blocks clicks on windows behind it
    mask: Region { item: hitArea }

    function isRunning(id) {
        const tl = ToplevelManager.toplevels.values
        for (let i = 0; i < tl.length; i++)
            if ((tl[i].appId || "").toLowerCase().indexOf(id) !== -1) return true
        return false
    }
    function launch(app) {
        const e = DesktopEntries.byId(app.id)
        if (e) e.execute()
        else Quickshell.execDetached(app.cmd)
    }

    // 0..1, eased in/out when the pointer enters/leaves, so the dock never snaps
    property real strength: pointer.hovered ? 1 : 0
    Behavior on strength { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    // pointer x in Row coordinates (the Row's own position is not affected by the shifts)
    readonly property real pointerX: pointer.point.position.x - row.x

    function magnifyAt(cx) {
        const d = Math.min(Math.abs(cx - pointerX), reach)
        return 1.0 + (maxMagnify - 1.0) * strength * Math.cos(d / reach * Math.PI / 2)
    }
    function growthAt(cx) { return iconSize * (magnifyAt(cx) - 1.0) }

    // base centres of the visible icons (fixed by the Row layout)
    readonly property var centers: {
        const cs = []
        for (let i = 0; i < row.children.length; i++) {
            const c = row.children[i]
            if (c.visible && c.magnify !== undefined) cs.push(c.x + c.width / 2)
        }
        return cs
    }
    readonly property real totalGrowth: centers.reduce((s, c) => s + growthAt(c), 0)
    // sideways shift for something centred at cx: half of its own growth plus all growth to its
    // left, re-centred so the dock widens evenly on both sides
    function shiftAt(cx) {
        let s = -totalGrowth / 2
        for (const c of centers) {
            if (c < cx - 0.5) s += growthAt(c)
            else if (Math.abs(c - cx) <= 0.5) s += growthAt(c) / 2
        }
        return s
    }

    Item {
        id: dockArea
        anchors.fill: parent
        // on the parent of every icon, so it keeps tracking while the pointer is over an icon
        HoverHandler { id: pointer }

        Item {
            id: hitArea
            anchors { bottom: glass.bottom; horizontalCenter: glass.horizontalCenter }
            width: glass.width + 16
            height: glass.height + 24
        }

        Glass {
            id: glass
            anchors { bottom: parent.bottom; bottomMargin: 12; horizontalCenter: parent.horizontalCenter }
            width: row.implicitWidth + 24 + dock.totalGrowth
            height: 74
            radius: 26
        }

        Row {
            id: row
            anchors { bottom: glass.bottom; bottomMargin: 11; horizontalCenter: parent.horizontalCenter }
            spacing: 10

            DockItem {
                label: "Launcher"
                glyph: "grid"
                magnify: dock.magnifyAt(x + width / 2)
                shift: dock.shiftAt(x + width / 2)
                onClicked: dock.shell.toggleLauncher(false)
            }
            Repeater {
                model: Theme.pinned
                DockItem {
                    required property var modelData
                    label: modelData.name
                    iconName: modelData.icon
                    running: dock.isRunning(modelData.id)
                    magnify: dock.magnifyAt(x + width / 2)
                    shift: dock.shiftAt(x + width / 2)
                    onClicked: dock.launch(modelData)
                }
            }
            DockItem {
                // the app list loads asynchronously, so bind to it (byId() alone is not re-evaluated)
                readonly property var entry: DesktopEntries.applications.values.find(e => e.id === "glacier-installer") ?? null
                visible: entry !== null
                label: "Install Glacier OS"
                iconName: "system-software-install"
                magnify: dock.magnifyAt(x + width / 2)
                shift: dock.shiftAt(x + width / 2)
                onClicked: if (entry) entry.execute()
            }
            Item {
                id: divider
                width: 1; height: dock.iconSize
                transform: Translate { x: dock.shiftAt(divider.x + 0.5) }
                Rectangle { anchors.centerIn: parent; width: 1; height: 40; color: Qt.rgba(1, 1, 1, 0.3) }
            }
            DockItem {
                label: "Packages"
                glyph: "store"
                magnify: dock.magnifyAt(x + width / 2)
                shift: dock.shiftAt(x + width / 2)
                onClicked: dock.shell.toggleLauncher(true)
            }
        }
    }
}
