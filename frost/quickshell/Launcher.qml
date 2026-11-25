import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls

// Spotlight-style launcher: apps from .desktop entries + floe package search.
PanelWindow {
    id: win
    required property var shell

    visible: shell.launcherOpen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Qt.rgba(0, 0, 0, 0.18)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "frost-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var packages: []
    property int sel: 0
    readonly property string query: input.text.trim()
    readonly property bool pkgMode: shell.launcherPackages

    readonly property var apps: {
        if (pkgMode) return []
        const q = query.toLowerCase()
        const all = DesktopEntries.applications.values.filter(e => !e.noDisplay)
        const hits = q === "" ? all : all.filter(e => e.name.toLowerCase().indexOf(q) !== -1
                                              || (e.genericName || "").toLowerCase().indexOf(q) !== -1)
        return hits.sort((a, b) => a.name.localeCompare(b.name)).slice(0, 8)
    }
    readonly property var results: apps.map(e => ({ kind: "app", entry: e }))
        .concat(packages.slice(0, pkgMode ? 12 : 5).map(p => ({ kind: "pkg", pkg: p })))

    onVisibleChanged: {
        if (visible) {
            packages = []; sel = 0
            input.text = shell.pendingQuery
            shell.pendingQuery = ""
            input.forceActiveFocus()
        }
    }
    onQueryChanged: { sel = 0; searchDelay.restart() }

    Timer {
        id: searchDelay
        interval: 280
        onTriggered: {
            if (win.query.length < 2) { win.packages = []; return }
            search.command = ["floe", "search", "--json", win.query]
            search.running = true
        }
    }
    Process {
        id: search
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.packages = JSON.parse(text) } catch (e) { win.packages = [] }
            }
        }
    }

    function run(r) {
        if (!r) return
        if (r.kind === "app") {
            r.entry.execute()
        } else {
            const n = r.pkg.name
            if (!/^[a-z0-9@._+-]+$/.test(n)) return
            const verb = r.pkg.installed ? "info" : "install"
            Quickshell.execDetached(["foot", "--title", "floe", "-e", "bash", "-c",
                "floe " + verb + " " + n + "; echo; read -r -p 'Press Enter to close' _"])
        }
        shell.launcherOpen = false
    }

    MouseArea { anchors.fill: parent; onClicked: win.shell.launcherOpen = false }

    Glass {
        id: box
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.16 }
        width: Math.min(640, parent.width - 40)
        height: header.height + (list.count > 0 ? list.contentHeight + 17 : 0)
        radius: 24
        under: 0.45
        MouseArea { anchors.fill: parent }   // swallow clicks

        Row {
            id: header
            x: 20
            width: parent.width - 40
            height: 62
            spacing: 12
            Image {
                anchors.verticalCenter: parent.verticalCenter
                source: Theme.icon(win.pkgMode ? "store" : "search")
                sourceSize.width: 20; sourceSize.height: 20
            }
            TextField {
                id: input
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 32
                placeholderText: win.pkgMode ? "Search floe packages…" : "Search apps and packages…"
                placeholderTextColor: Theme.fg3
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 19
                font.weight: Font.Medium
                background: null
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) { win.shell.launcherOpen = false; event.accepted = true }
                    else if (event.key === Qt.Key_Down) { win.sel = Math.min(win.results.length - 1, win.sel + 1); event.accepted = true }
                    else if (event.key === Qt.Key_Up) { win.sel = Math.max(0, win.sel - 1); event.accepted = true }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { win.run(win.results[win.sel]); event.accepted = true }
                }
            }
        }
        Rectangle { anchors.top: header.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.12); visible: list.count > 0 }

        ListView {
            id: list
            anchors { top: header.bottom; topMargin: 9; left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 }
            height: Math.min(contentHeight, 420)
            clip: true
            interactive: contentHeight > height
            model: win.results
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width
                height: 50
                radius: 14
                color: index === win.sel ? Theme.hover : "transparent"
                Row {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 12
                    Image {
                        visible: modelData.kind === "app"
                        source: modelData.kind === "app" ? Quickshell.iconPath(modelData.entry.icon, "application-x-executable") : ""
                        sourceSize.width: 34; sourceSize.height: 34
                    }
                    Rectangle {
                        visible: modelData.kind === "pkg"
                        width: 34; height: 34; radius: 10
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#b28cff" }
                            GradientStop { position: 1; color: "#5a4bff" }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.kind === "pkg" ? modelData.pkg.name.charAt(0).toUpperCase() : ""
                            color: "white"; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.ExtraBold
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: modelData.kind === "app" ? modelData.entry.name : modelData.pkg.name
                            color: Theme.fg; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Text {
                            width: list.width - 160
                            elide: Text.ElideRight
                            text: modelData.kind === "app" ? (modelData.entry.genericName || "Application")
                                  : (modelData.pkg.installed ? "Installed · " : modelData.pkg.repo + " · ") + modelData.pkg.version + " — " + modelData.pkg.description
                            color: Theme.fg3; font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                }
                Text {
                    visible: index === win.sel
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: modelData.kind === "app" ? "↵ Open" : (modelData.pkg.installed ? "↵ Info" : "↵ Install")
                    color: Theme.fg3; font.family: Theme.font; font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: win.sel = index
                    onClicked: win.run(modelData)
                }
            }
        }
    }
}
