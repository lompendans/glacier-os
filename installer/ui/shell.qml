//@ pragma UseQApplication
//@ pragma IconTheme Papirus-Dark
// Glacier Installer — front end for /usr/local/bin/glacier-install (runs it via sudo).
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

ShellRoot {
    id: app

    // ---- state ----
    property int page: 0                         // 0 welcome · 1 disk · 2 account · 3 region · 4 review · 5 installing · 6 done
    readonly property var steps: ["Welcome", "Disk", "Account", "Region", "Install"]
    property var disks: []
    property string disk: ""
    property string fullName: ""
    property string userName: ""
    property bool userEdited: false
    property string password: ""
    property string password2: ""
    property string hostName: "glacier"
    property var timezones: []
    property string timezone: "UTC"
    property bool autologin: false
    property bool confirmed: false
    property int progress: 0
    property string status: ""
    property string error: ""

    readonly property bool userValid: /^[a-z_][a-z0-9_-]{0,31}$/.test(userName)
                                      && ["root", "bin", "daemon", "nobody"].indexOf(userName) === -1
    readonly property bool hostValid: /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(hostName)
    readonly property bool passValid: password.length >= 4 && password === password2
    readonly property bool canNext: page === 0 || (page === 1 && disk !== "")
                                    || (page === 2 && userValid && hostValid && passValid && fullName.indexOf(":") === -1)
                                    || (page === 3 && timezone !== "")

    onFullNameChanged: if (!userEdited) userName = fullName.trim().split(/\s+/)[0].toLowerCase().replace(/[^a-z0-9_-]/g, "")

    // `qs -p /usr/share/glacier-installer ipc call installer goto 2` — used by the headless UI test
    IpcHandler {
        target: "installer"
        function goto(n: int): void { if (n >= 0 && n <= 4) app.page = n }
    }

    // ---- processes ----
    Process {
        id: diskProc
        command: ["sudo", "-n", "/usr/local/bin/glacier-install", "--list-disks"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { app.disks = JSON.parse(text) } catch (e) { app.disks = [] } } }
    }
    Process {
        command: ["timedatectl", "list-timezones"]
        running: true
        stdout: StdioCollector { onStreamFinished: app.timezones = text.split("\n").filter(l => l.length > 0) }
    }
    Process {
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]
        running: true
        stdout: StdioCollector { onStreamFinished: { const t = text.trim(); if (t !== "") app.timezone = t } }
    }
    Process {
        id: installer
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                const m = /^PROGRESS (-?\d+) (.*)$/.exec(line)
                if (!m) return
                const p = parseInt(m[1])
                if (p < 0) { app.error = m[2]; return }
                app.progress = p
                app.status = m[2]
            }
        }
        stderr: SplitParser { onRead: line => { if (line.startsWith("ERROR ")) app.error = line.substring(6) } }
        onStarted: { write(app.password + "\n"); app.password = ""; app.password2 = "" }
        onExited: (code, status) => {
            if (code === 0 && app.progress === 100) app.page = 6
            else if (app.error === "") app.error = "The installer stopped unexpectedly (exit code " + code + ")."
        }
    }

    function startInstall() {
        const cmd = ["sudo", "-n", "/usr/local/bin/glacier-install", "--disk", disk, "--user", userName,
                     "--fullname", fullName.trim(), "--hostname", hostName, "--timezone", timezone, "--yes-wipe-disk"]
        if (autologin) cmd.push("--autologin")
        error = ""; progress = 0; status = "Starting"
        installer.command = cmd
        page = 5
        installer.running = true
    }

    // ---- window ----
    FloatingWindow {
        id: win
        title: "Install Glacier OS"
        implicitWidth: 880
        implicitHeight: 580
        color: "transparent"
        onVisibleChanged: if (!visible && !installer.running) Qt.quit()

        Rectangle {   // glass body (Hyprland blurs what is behind the window)
            anchors.fill: parent
            radius: 22
            color: Qt.rgba(0.055, 0.07, 0.14, 0.55)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.28)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.20, 0.24, 0.36, 0.62) }
                GradientStop { position: 1.0; color: Qt.rgba(0.05, 0.07, 0.14, 0.62) }
            }
        }

        // sidebar with steps
        Column {
            x: 28; y: 30
            width: 190
            spacing: 6
            Row {
                spacing: 10
                bottomPadding: 22
                Rectangle {
                    width: 36; height: 36; radius: 11
                    gradient: Gradient { GradientStop { position: 0; color: "#5ac8fa" } GradientStop { position: 1; color: "#8a7dff" } }
                    Image { anchors.centerIn: parent; source: "peak.svg"; sourceSize.width: 20; sourceSize.height: 20 }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Glacier OS"; color: "white"; font.family: "Inter"; font.pixelSize: 17; font.weight: Font.Bold }
            }
            Repeater {
                model: app.steps
                Rectangle {
                    required property string modelData
                    required property int index
                    // the last step stays "current" while installing (page 5) and is done at page 6
                    readonly property bool current: Math.min(app.page, 4) === index && app.page < 6
                    readonly property bool done: app.page > index && !current
                    width: 190; height: 38; radius: 12
                    color: current ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                    Row {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Rectangle {
                            width: 20; height: 20; radius: 10
                            color: done ? "#3ee08f" : (current ? "#5ac8fa" : Qt.rgba(1, 1, 1, 0.12))
                            Text { anchors.centerIn: parent; text: done ? "✓" : String(index + 1); color: "white"; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.Bold }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData; color: current ? "white" : Qt.rgba(1, 1, 1, 0.6); font.family: "Inter"; font.pixelSize: 14; font.weight: current ? Font.DemiBold : Font.Normal }
                    }
                }
            }
        }
        Rectangle { x: 240; y: 24; width: 1; height: parent.height - 48; color: Qt.rgba(1, 1, 1, 0.1) }

        // top-right window close button (hidden while an install is actively writing to disk)
        Rectangle {
            visible: !installer.running
            anchors { top: parent.top; right: parent.right; topMargin: 18; rightMargin: 18 }
            width: 30; height: 30; radius: 15
            color: closeMouse.pressed ? "#c23a4b" : (closeMouse.containsMouse ? "#e5485b" : Qt.rgba(1, 1, 1, 0.12))
            border.width: 1
            border.color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.16)
            Behavior on color { ColorAnimation { duration: 120 } }
            Image {
                anchors.centerIn: parent
                source: "close.svg"
                sourceSize.width: 13; sourceSize.height: 13
                opacity: closeMouse.containsMouse ? 1.0 : 0.8
            }
            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: Qt.quit()
            }
        }

        // page area
        Item {
            id: pageArea
            x: 270; y: 34
            width: parent.width - 300
            height: parent.height - 120

            // 0 — welcome
            Column {
                visible: app.page === 0
                width: parent.width
                spacing: 14
                Text { text: "Install Glacier OS"; color: "white"; font.family: "Inter"; font.pixelSize: 30; font.weight: Font.ExtraBold }
                Text { width: parent.width; wrapMode: Text.WordWrap; color: Qt.rgba(1, 1, 1, 0.75); font.family: "Inter"; font.pixelSize: 14; lineHeight: 1.3
                       text: "This puts Glacier OS — the Frost liquid-glass desktop and the floe package manager — on this computer. It takes a few minutes and works without an internet connection." }
                Rectangle {
                    width: parent.width; height: 84; radius: 16
                    color: Qt.rgba(1, 0.42, 0.48, 0.14); border.color: Qt.rgba(1, 0.42, 0.48, 0.45)
                    Text { anchors.fill: parent; anchors.margins: 16; wrapMode: Text.WordWrap; color: "white"; font.family: "Inter"; font.pixelSize: 13; lineHeight: 1.3
                           text: "The disk you choose will be completely erased. Back up anything you want to keep first. Installing alongside another operating system is not supported yet." }
                }
            }

            // 1 — disk
            Column {
                visible: app.page === 1
                width: parent.width
                spacing: 12
                Text { text: "Where should Glacier go?"; color: "white"; font.family: "Inter"; font.pixelSize: 24; font.weight: Font.Bold }
                Text { color: Qt.rgba(1, 1, 1, 0.7); font.family: "Inter"; font.pixelSize: 13; text: "The whole disk is used. The live USB/DVD itself is not listed." }
                Repeater {
                    model: app.disks
                    Rectangle {
                        required property var modelData
                        width: pageArea.width; height: 64; radius: 16
                        color: app.disk === modelData.path ? Qt.rgba(0.35, 0.78, 0.98, 0.25) : (dm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.2))
                        border.color: app.disk === modelData.path ? "#5ac8fa" : Qt.rgba(1, 1, 1, 0.12)
                        Image { x: 16; anchors.verticalCenter: parent.verticalCenter; source: Quickshell.iconPath("drive-harddisk", "drive-harddisk"); sourceSize.width: 36; sourceSize.height: 36 }
                        Column {
                            x: 66; anchors.verticalCenter: parent.verticalCenter
                            Text { text: modelData.model + " · " + modelData.size; color: "white"; font.family: "Inter"; font.pixelSize: 15; font.weight: Font.DemiBold }
                            Text { text: modelData.path; color: Qt.rgba(1, 1, 1, 0.55); font.family: "JetBrains Mono"; font.pixelSize: 12 }
                        }
                        MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; onClicked: app.disk = modelData.path }
                    }
                }
                Text { visible: app.disks.length === 0; color: "#ffcb6b"; font.family: "Inter"; font.pixelSize: 13; text: diskProc.running ? "Looking for disks…" : "No disks found to install to." }
            }

            // 2 — account
            Column {
                visible: app.page === 2
                width: parent.width
                spacing: 10
                Text { text: "Who will use this computer?"; color: "white"; font.family: "Inter"; font.pixelSize: 24; font.weight: Font.Bold; bottomPadding: 6 }
                GlassField { label: "Your name"; text: app.fullName; onEdited: v => app.fullName = v }
                GlassField { label: "User name"; text: app.userName; mono: true; bad: app.userName !== "" && !app.userValid
                             hint: "lowercase letters, digits, - and _"; onEdited: v => { app.userEdited = true; app.userName = v } }
                Row {
                    spacing: 12
                    GlassField { width: (pageArea.width - 12) / 2; label: "Password"; secret: true; text: app.password; onEdited: v => app.password = v }
                    GlassField { width: (pageArea.width - 12) / 2; label: "Confirm password"; secret: true; text: app.password2
                                 bad: app.password2 !== "" && app.password2 !== app.password; hint: "must match"; onEdited: v => app.password2 = v }
                }
                GlassField { label: "Computer name"; text: app.hostName; mono: true; bad: !app.hostValid; hint: "letters, digits and -"; onEdited: v => app.hostName = v }
                Row {
                    spacing: 10
                    Switch { id: auto; checked: app.autologin; onToggled: app.autologin = checked }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Log in automatically"; color: "white"; font.family: "Inter"; font.pixelSize: 13 }
                }
            }

            // 3 — region
            Column {
                visible: app.page === 3
                width: parent.width
                spacing: 10
                Text { text: "Time zone"; color: "white"; font.family: "Inter"; font.pixelSize: 24; font.weight: Font.Bold }
                GlassField { id: tzSearch; label: "Search"; text: ""; onEdited: v => tzList.filter = v.toLowerCase() }
                ListView {
                    id: tzList
                    property string filter: ""
                    width: parent.width; height: 270
                    clip: true
                    model: app.timezones.filter(t => filter === "" || t.toLowerCase().indexOf(filter) !== -1)
                    delegate: Rectangle {
                        required property string modelData
                        width: tzList.width; height: 34; radius: 10
                        color: app.timezone === modelData ? Qt.rgba(0.35, 0.78, 0.98, 0.25) : (tm.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.replace(/_/g, " "); color: "white"; font.family: "Inter"; font.pixelSize: 13 }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; onClicked: app.timezone = modelData }
                    }
                }
                Text { text: "Selected: " + app.timezone; color: Qt.rgba(1, 1, 1, 0.7); font.family: "Inter"; font.pixelSize: 13 }
            }

            // 4 — review
            Column {
                visible: app.page === 4
                width: parent.width
                spacing: 12
                Text { text: "Ready to install"; color: "white"; font.family: "Inter"; font.pixelSize: 24; font.weight: Font.Bold }
                Rectangle {
                    width: parent.width; height: summary.implicitHeight + 28; radius: 16; color: Qt.rgba(0, 0, 0, 0.2)
                    Grid {
                        id: summary
                        x: 16; y: 14
                        columns: 2; rowSpacing: 8; columnSpacing: 20
                        // label, value, label, value, … (one grid cell per string)
                        Repeater {
                            model: ["Disk", app.disk !== "" ? app.disk + "  (will be erased)" : "", "Name", app.fullName, "User", app.userName,
                                    "Computer", app.hostName, "Time zone", app.timezone,
                                    "Sign-in", app.autologin ? "automatic" : "password", "Boot", "GRUB · BIOS and UEFI"]
                            Text {
                                required property string modelData
                                required property int index
                                // never empty: Grid skips zero-width cells, which would shift every later row
                                text: modelData !== "" ? modelData : "—"
                                color: index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.55) : "white"
                                font.family: "Inter"; font.pixelSize: 13
                            }
                        }
                    }
                }
                Row {
                    spacing: 10
                    CheckBox { id: ok; checked: app.confirmed; onToggled: app.confirmed = checked }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: pageArea.width - 50; wrapMode: Text.WordWrap
                           text: "I understand that everything on " + app.disk + " will be erased."; color: "white"; font.family: "Inter"; font.pixelSize: 13 }
                }
            }

            // 5 — installing / 6 — done
            Column {
                visible: app.page >= 5
                width: parent.width
                spacing: 16
                Text { text: app.page === 6 ? "All done" : (app.error !== "" ? "Installation failed" : "Installing Glacier OS"); color: "white"; font.family: "Inter"; font.pixelSize: 26; font.weight: Font.Bold }
                Text { width: parent.width; wrapMode: Text.WordWrap; font.family: "Inter"; font.pixelSize: 14
                       color: app.error !== "" ? "#ff8a96" : Qt.rgba(1, 1, 1, 0.75)
                       text: app.error !== "" ? app.error : (app.page === 6 ? "Remove the installation medium and restart to start using Glacier OS." : app.status + "…") }
                Rectangle {
                    visible: app.error === ""
                    width: parent.width; height: 14; radius: 7; color: Qt.rgba(1, 1, 1, 0.12)
                    Rectangle {
                        width: Math.max(14, parent.width * app.progress / 100); height: parent.height; radius: 7
                        gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#5ac8fa" } GradientStop { position: 1; color: "#8a7dff" } }
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }
                Text { visible: app.error === ""; text: app.progress + "%"; color: Qt.rgba(1, 1, 1, 0.55); font.family: "Inter"; font.pixelSize: 13 }
            }
        }

        // bottom buttons
        Row {
            anchors { right: parent.right; rightMargin: 30; bottom: parent.bottom; bottomMargin: 26 }
            spacing: 10
            GlassButton {
                visible: app.page > 0 && app.page < 5
                text: "Back"
                onClicked: app.page -= 1
            }
            GlassButton {
                visible: app.page < 4
                primary: true
                enabled: app.canNext
                text: app.page === 0 ? "Get started" : "Continue"
                onClicked: app.page += 1
            }
            GlassButton {
                visible: app.page === 4
                danger: true
                enabled: app.confirmed
                text: "Erase disk and install"
                onClicked: app.startInstall()
            }
            GlassButton {
                visible: app.page === 6 || (app.page === 5 && app.error !== "")
                primary: app.page === 6
                text: app.page === 6 ? "Restart now" : "Close"
                onClicked: app.page === 6 ? Quickshell.execDetached(["systemctl", "reboot"]) : Qt.quit()
            }
        }
    }

    component GlassButton: Button {
        id: b
        property bool primary: false
        property bool danger: false
        implicitHeight: 40
        leftPadding: 22; rightPadding: 22
        opacity: enabled ? 1 : 0.4
        Keys.onReturnPressed: if (enabled) clicked()
        contentItem: Text { text: b.text; color: "white"; font.family: "Inter"; font.pixelSize: 14; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle {
            radius: 20
            color: b.danger ? (b.down ? "#c23a4b" : "#e5485b") : b.primary ? (b.down ? "#3aa8da" : "#5ac8fa") : (b.hovered ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.12))
            border.width: b.activeFocus ? 2 : 1
            border.color: b.activeFocus ? "white" : Qt.rgba(1, 1, 1, 0.3)
        }
    }

    component GlassField: Column {
        id: f
        property string label
        property string text
        property string hint: ""
        property bool secret: false
        property bool mono: false
        property bool bad: false
        signal edited(string value)
        width: pageArea.width
        spacing: 4
        Text { text: f.label + (f.bad && f.hint !== "" ? " — " + f.hint : ""); color: f.bad ? "#ff8a96" : Qt.rgba(1, 1, 1, 0.6); font.family: "Inter"; font.pixelSize: 12 }
        TextField {
            width: f.width; height: 40
            text: f.text
            echoMode: f.secret ? TextInput.Password : TextInput.Normal
            color: "white"
            font.family: f.mono ? "JetBrains Mono" : "Inter"; font.pixelSize: 14
            leftPadding: 14
            onTextEdited: f.edited(text)
            background: Rectangle {
                radius: 12
                color: Qt.rgba(0, 0, 0, 0.25)
                border.width: parent.activeFocus ? 2 : 1
                border.color: f.bad ? "#ff6b7a" : (parent.activeFocus ? "#5ac8fa" : Qt.rgba(1, 1, 1, 0.15))
            }
        }
    }
}
