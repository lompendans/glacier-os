//@ pragma UseQApplication
//@ pragma IconTheme Papirus-Dark
// Frost Greeter — Glacier OS liquid-glass login screen (talks to greetd via Quickshell.Services.Greetd).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import QtQuick
import QtQuick.Controls

ShellRoot {
    id: root

    property var users: []
    property int selectedIndex: 0
    readonly property var currentUser: users.length > 0 ? users[Math.min(selectedIndex, users.length - 1)] : null
    property string pendingPassword: ""
    property string errorText: ""
    property bool busy: false
    property string kbLabel: ""

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // Load regular human users (UID 1000..60000 with a real login shell)
    Process {
        id: userProc
        command: ["awk", "-F:", "$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ { print $1 \"\\t\" $5 }", "/etc/passwd"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const list = []
                for (const line of text.split("\n")) {
                    if (line.trim() === "") continue
                    const parts = line.split("\t")
                    const uname = parts[0]
                    const gecos = (parts[1] || "").split(",")[0].trim()
                    list.push({ name: uname, display: gecos !== "" ? gecos : uname })
                }
                root.users = list
            }
        }
    }

    // Show configured keyboard layout badge (e.g. US, TR, DE)
    Process {
        id: kbProc
        command: ["sh", "-c", "sed -n 's/.*kb_layout[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' /usr/share/frost/greeter/hyprland.lua | head -1"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.kbLabel = text.trim().toUpperCase() }
    }

    function initials(name) {
        const parts = (name || "?").trim().split(/\s+/)
        if (parts.length >= 2) return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
        return (parts[0] || "?").substring(0, 2).toUpperCase()
    }

    function submit(username, password) {
        const u = (username || "").trim()
        if (u === "" || root.busy) return
        root.errorText = ""
        if (!Greetd.available) {
            root.errorText = "Login service unavailable"
            return
        }
        root.busy = true
        root.pendingPassword = password
        if (Greetd.state === GreetdState.Authenticating) Greetd.cancelSession()
        Greetd.createSession(u)
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                Greetd.respond(root.pendingPassword)
                root.pendingPassword = ""
            } else if (error && message !== "") {
                root.errorText = message
            }
        }
        function onAuthFailure(message) {
            root.busy = false
            root.pendingPassword = ""
            root.errorText = message !== "" ? message : "Incorrect password"
        }
        function onReadyToLaunch() {
            Greetd.launch(["start-hyprland"])
        }
        function onLaunched() {
            Quickshell.execDetached(["hyprctl", "dispatch", "exit"])
            Qt.quit()
        }
        function onError(err) {
            root.busy = false
            root.pendingPassword = ""
            root.errorText = err !== "" ? err : "Authentication error"
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Component {
            PanelWindow {
                id: win
                required property var modelData
                screen: modelData

                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: Qt.rgba(0.03, 0.05, 0.12, 0.28)
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "frost-greeter"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

                // Top-center lock/login clock
                Column {
                    anchors { top: parent.top; topMargin: Math.max(48, parent.height * 0.10); horizontalCenter: parent.horizontalCenter }
                    spacing: 4
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: "white"
                        font.family: "Inter"
                        font.pixelSize: 72
                        font.weight: Font.ExtraBold
                        font.letterSpacing: -2
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                        color: Qt.rgba(1, 1, 1, 0.78)
                        font.family: "Inter"
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }
                }

                // Centered liquid-glass login card
                Rectangle {
                    id: card
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 36
                    width: 360
                    height: cardCol.implicitHeight + 52
                    radius: 26
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.28)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0.20, 0.24, 0.36, 0.58) }
                        GradientStop { position: 1.0; color: Qt.rgba(0.05, 0.07, 0.14, 0.68) }
                    }

                    Column {
                        id: cardCol
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 28 }
                        spacing: 16

                        // Avatar circle
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 68; height: 68; radius: 34
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.35)
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#5ac8fa" }
                                GradientStop { position: 1.0; color: "#8a7dff" }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root.currentUser ? root.initials(root.currentUser.display) : "G"
                                color: "white"
                                font.family: "Inter"
                                font.pixelSize: 24
                                font.weight: Font.Bold
                            }
                        }

                        // Active user name
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.currentUser ? root.currentUser.display : "Glacier OS"
                                color: "white"
                                font.family: "Inter"
                                font.pixelSize: 20
                                font.weight: Font.Bold
                            }
                            Text {
                                visible: root.currentUser !== null && root.currentUser.display !== root.currentUser.name
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.currentUser ? "@" + root.currentUser.name : ""
                                color: Qt.rgba(1, 1, 1, 0.55)
                                font.family: "JetBrains Mono"
                                font.pixelSize: 12
                            }
                        }

                        // User switcher pills (shown when multiple users exist)
                        Flow {
                            visible: root.users.length > 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6
                            Repeater {
                                model: root.users
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: uText.implicitWidth + 20; height: 28; radius: 14
                                    color: root.selectedIndex === index ? Qt.rgba(0.35, 0.78, 0.98, 0.32) : (uMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08))
                                    border.width: 1
                                    border.color: root.selectedIndex === index ? "#5ac8fa" : Qt.rgba(1, 1, 1, 0.16)
                                    Text { id: uText; anchors.centerIn: parent; text: modelData.name; color: "white"; font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium }
                                    MouseArea {
                                        id: uMouse; anchors.fill: parent; hoverEnabled: true
                                        onClicked: { root.selectedIndex = index; root.errorText = ""; passField.text = ""; passField.forceActiveFocus() }
                                    }
                                }
                            }
                        }

                        // Fallback username input if /etc/passwd returned no UID >= 1000 user
                        TextField {
                            id: userField
                            visible: root.users.length === 0
                            width: parent.width; height: 42
                            placeholderText: "Username"
                            placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                            color: "white"
                            font.family: "Inter"; font.pixelSize: 14
                            leftPadding: 14; rightPadding: 14
                            Keys.onReturnPressed: passField.forceActiveFocus()
                            background: Rectangle {
                                radius: 13
                                color: Qt.rgba(0, 0, 0, 0.28)
                                border.width: parent.activeFocus ? 2 : 1
                                border.color: parent.activeFocus ? "#5ac8fa" : Qt.rgba(1, 1, 1, 0.18)
                            }
                        }

                        // Password input
                        TextField {
                            id: passField
                            width: parent.width; height: 44
                            echoMode: TextInput.Password
                            placeholderText: root.busy ? "Signing in…" : "Enter password"
                            placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                            color: "white"
                            font.family: "Inter"; font.pixelSize: 14
                            leftPadding: 14; rightPadding: 14
                            enabled: !root.busy
                            focus: true
                            Component.onCompleted: forceActiveFocus()
                            Keys.onReturnPressed: {
                                const u = root.currentUser ? root.currentUser.name : userField.text
                                root.submit(u, text)
                                text = ""
                            }
                            background: Rectangle {
                                radius: 13
                                color: Qt.rgba(0, 0, 0, 0.28)
                                border.width: parent.activeFocus ? 2 : 1
                                border.color: root.errorText !== "" ? "#ff6b7a" : (parent.activeFocus ? "#5ac8fa" : Qt.rgba(1, 1, 1, 0.18))
                            }
                        }

                        // Error message
                        Text {
                            visible: root.errorText !== ""
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: root.errorText
                            color: "#ff8a96"
                            font.family: "Inter"
                            font.pixelSize: 13
                        }

                        // Sign in button
                        Button {
                            id: signBtn
                            width: parent.width; height: 42
                            enabled: !root.busy
                            opacity: enabled ? 1 : 0.6
                            onClicked: {
                                const u = root.currentUser ? root.currentUser.name : userField.text
                                root.submit(u, passField.text)
                                passField.text = ""
                            }
                            contentItem: Text {
                                text: root.busy ? "Signing in…" : "Sign in"
                                color: "white"
                                font.family: "Inter"; font.pixelSize: 14; font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 21
                                color: signBtn.down ? "#3aa8da" : (signBtn.hovered ? "#6dd0ff" : "#5ac8fa")
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.35)
                            }
                        }
                    }
                }

                // Bottom-left Glacier branding + keyboard layout badge
                Row {
                    anchors { left: parent.left; bottom: parent.bottom; margins: 20 }
                    spacing: 10
                    Rectangle {
                        height: 34; width: brandRow.implicitWidth + 22; radius: 17
                        color: Qt.rgba(0.08, 0.11, 0.20, 0.55)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
                        Row {
                            id: brandRow
                            anchors.centerIn: parent
                            spacing: 8
                            Image { anchors.verticalCenter: parent.verticalCenter; source: "icons/peak.svg"; sourceSize.width: 16; sourceSize.height: 16 }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Glacier OS"; color: "white"; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold }
                        }
                    }
                    Rectangle {
                        visible: root.kbLabel !== ""
                        height: 34; width: kbText.implicitWidth + 22; radius: 17
                        color: Qt.rgba(0.08, 0.11, 0.20, 0.55)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
                        Text { id: kbText; anchors.centerIn: parent; text: root.kbLabel; color: Qt.rgba(1, 1, 1, 0.85); font.family: "JetBrains Mono"; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                }

                // Bottom-right power controls
                Row {
                    anchors { right: parent.right; bottom: parent.bottom; margins: 20 }
                    spacing: 8
                    PowerPill { icon: "reboot"; label: "Restart"; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
                    PowerPill { icon: "power"; label: "Shut Down"; onClicked: Quickshell.execDetached(["systemctl", "poweroff"]) }
                }
            }
        }
    }

    component PowerPill: Rectangle {
        id: pill
        property string icon: ""
        property string label: ""
        signal clicked()
        height: 34
        width: pRow.implicitWidth + 24
        radius: 17
        color: pMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0.08, 0.11, 0.20, 0.55)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.22)
        Behavior on color { ColorAnimation { duration: 120 } }
        Row {
            id: pRow
            anchors.centerIn: parent
            spacing: 7
            Image { anchors.verticalCenter: parent.verticalCenter; source: "icons/" + pill.icon + ".svg"; sourceSize.width: 15; sourceSize.height: 15 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: pill.label; color: "white"; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.Medium }
        }
        MouseArea { id: pMouse; anchors.fill: parent; hoverEnabled: true; onClicked: pill.clicked() }
    }
}
