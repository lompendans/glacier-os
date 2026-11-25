//@ pragma UseQApplication
//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Frost — the Glacier OS desktop shell.
ShellRoot {
    id: root

    property bool launcherOpen: false
    property bool launcherPackages: false
    property bool ccOpen: false
    property bool wifiOn: true
    property int packageCount: 0
    property string pendingQuery: ""   // text the launcher opens with (see ipc "search")

    function toggleLauncher(packages) {
        ccOpen = false
        if (launcherOpen && launcherPackages === packages) { launcherOpen = false; return }
        launcherPackages = packages
        launcherOpen = true
    }
    function toggleControlCenter() {
        launcherOpen = false
        ccOpen = !ccOpen
    }

    // `qs ipc call frost launcher` etc. — used by the Hyprland keybinds.
    IpcHandler {
        target: "frost"
        function launcher(): void { root.toggleLauncher(false) }
        function packages(): void { root.toggleLauncher(true) }
        function controlCenter(): void { root.toggleControlCenter() }
        // open the launcher pre-filled, e.g. `qs ipc call frost search krita`
        function search(query: string): void {
            root.ccOpen = false
            root.launcherOpen = false
            root.pendingQuery = query
            root.launcherPackages = false
            root.launcherOpen = true
        }
    }

    Process { id: countProc; command: ["floe", "list", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { root.packageCount = JSON.parse(text).length } catch (e) {} } } }
    Process { id: wifiProc; command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector { onStreamFinished: root.wifiOn = text.trim() === "enabled" } }
    Timer {
        interval: 15000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { countProc.running = true; wifiProc.running = true }
    }
    onLauncherOpenChanged: if (!launcherOpen) countProc.running = true

    Variants {
        model: Quickshell.screens
        delegate: Component {
            Scope {
                required property var modelData
                Bar { screen: modelData; shell: root }
                Dock { screen: modelData; shell: root }
            }
        }
    }
    Launcher { shell: root }

    // Click anywhere outside the Control Center to close it: an invisible full-screen layer
    // just below the panel (Top layer; the panel itself is on the Overlay layer).
    PanelWindow {
        visible: root.ccOpen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "frost-cc-dismiss"
        MouseArea { anchors.fill: parent; onClicked: root.ccOpen = false }
    }
    ControlCenter { shell: root }
}
