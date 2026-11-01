import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Claude Agent Viz: sơ đồ lead / swarm / advisor của Claude Code, vẽ trực tiếp.
// Dữ liệu: collector.py (hook của Claude Code) ghi ~/.cache/claude-agentviz/state.json.
// Cửa sổ thường (có thanh tiêu đề). Hook tự mở khi có subagent chạy (tác vụ phức tạp).
// Mở: claude-agentviz   IPC: qs -p ~/dev/cael-src/apps/agentviz/shell.qml ipc call agentviz close|status
ShellRoot {
    id: app

    // ------------------------------------------------------------------ màu (giống ảnh)
    readonly property color bg: "#15171c"
    readonly property color fg: "#d6d8de"
    readonly property color muted: "#7c818c"
    readonly property color cLead: "#e0805a"
    readonly property color cSwarm: "#7aa7f0"
    readonly property color cFork: "#67c98a"
    readonly property color cAdv: "#a69af0"
    readonly property color cErr: "#f07a7a"
    readonly property string mono: "CaskaydiaCove Nerd Font Mono"

    // ------------------------------------------------------------------ dữ liệu
    property var st: ({})
    property real now: Date.now() / 1000
    readonly property var s: (st.sessions ?? {})[st.active ?? ""] ?? null
    readonly property var subsAll: s ? Object.values(s.subs ?? {}).sort((a, b) => a.start - b.start) : []
    readonly property var swarm: subsAll.filter(x => !x.advisor)
    readonly property var forks: swarm.filter(x => x.fork)
    readonly property var advisorRuns: subsAll.filter(x => x.advisor)
    readonly property bool advisorRunning: advisorRuns.some(x => x.status === "running")
    readonly property int running: swarm.filter(x => x.status === "running").length
    readonly property int maxTools: Math.max(8, ...swarm.map(x => x.tools))
    readonly property string phase: s?.phase ?? "idle"
    readonly property string leadName: cap(s?.model ?? "claude")

    // ------------------------------------------------------------------ trạng thái
    readonly property bool live: !!s && (s.busy || subsAll.some(x => x.status === "running"))
    // chưa có tác vụ (rảnh, hoặc xong > 15s): chỉ hiện popup nhỏ "model · pending"
    readonly property bool compact: !live && now - (s?.doneAt ?? 0) > 15
    // model mặc định từ ~/.claude/settings.json khi chưa có phiên nào
    property string defaultModel: "sonnet"
    readonly property string popupModel: cap(s?.model && s.model !== "?" ? s.model : defaultModel)
    readonly property size fullSize: Qt.size(800, 640)
    readonly property size popupSize: Qt.size(300, 96)

    FileView {
        path: Quickshell.env("HOME") + "/.claude/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { app.defaultModel = JSON.parse(text()).model || "sonnet"; } catch (e) {} }
    }

    // đổi kích thước + đặt về góc trên phải qua Lua (minimize.lua: cael_place_tr)
    Process { id: placer }
    function place() {
        const z = compact ? popupSize : fullSize;
        placer.exec(["hyprctl", "eval", `cael_place_tr('Claude Agent Viz', ${z.width}, ${z.height})`]);
    }
    onCompactChanged: place()
    Timer { interval: 250; running: true; onTriggered: app.place() }

    function cap(m) { return (m ?? "").replace(/^\w/, c => c.toUpperCase()); }
    function ago(t) {
        const d = Math.max(0, Math.round(now - t));
        return d < 60 ? d + "s" : Math.round(d / 60) + "m";
    }
    function effortBlocks(e) {
        const n = ({ low: 1, medium: 2, high: 3, xhigh: 4, max: 5 })[e] ?? 0;
        return "▮".repeat(n) + "▯".repeat(5 - n);
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.cache/claude-agentviz/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { app.st = JSON.parse(text()); } catch (e) {} }
    }
    Timer {
        interval: 700; running: true; repeat: true
        onTriggered: { app.now = Date.now() / 1000; file.reload(); }
    }

    IpcHandler {
        target: "agentviz"
        function close(): void { Qt.quit(); }
        function status(): string { return JSON.stringify({ live: app.live, phase: app.phase, swarm: app.swarm.length, running: app.running }); }
    }

    // ------------------------------------------------------------------ thành phần
    component T: Text {
        color: app.fg
        font.family: app.mono
        font.pixelSize: 12
    }
    component Box: Rectangle {
        property color accent: app.muted
        property bool lit: false
        color: lit ? Qt.rgba(accent.r, accent.g, accent.b, 0.10) : "transparent"
        border.color: lit ? accent : Qt.rgba(accent.r, accent.g, accent.b, 0.55)
        border.width: lit ? 2 : 1
        radius: 3
        Behavior on color { ColorAnimation { duration: 250 } }
    }
    // đường nối nét đứt dọc, có chấm chạy khi đang hoạt động
    component Wire: Item {
        property bool active: false
        property color tint: app.muted
        implicitWidth: 10
        implicitHeight: 22
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3
            Repeater {
                model: Math.floor(parent.parent.height / 6)
                Rectangle { width: 1; height: 3; color: app.muted; opacity: 0.6 }
            }
        }
        Rectangle {
            id: dot
            visible: parent.active
            width: 5; height: 5; radius: 3
            color: parent.tint
            anchors.horizontalCenter: parent.horizontalCenter
            NumberAnimation on y {
                running: dot.visible; loops: Animation.Infinite
                from: 0; to: dot.parent.height - 5; duration: 900
            }
        }
    }
    component Mark: RowLayout {
        property string label
        property bool on: false
        property color tint: app.cAdv
        spacing: 6
        T { text: parent.on ? "◆" : "◇"; color: parent.on ? parent.tint : app.muted }
        T { text: parent.label; color: parent.on ? parent.tint : app.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    }

    // ------------------------------------------------------------------ cửa sổ
    FloatingWindow {
        id: win
        title: "Claude Agent Viz"
        implicitWidth: app.compact ? app.popupSize.width : app.fullSize.width
        implicitHeight: app.compact ? app.popupSize.height : app.fullSize.height
        minimumSize: app.compact ? Qt.size(240, 80) : Qt.size(720, 560)
        color: app.bg
        visible: true
        onVisibleChanged: if (!visible) Qt.quit()

        // ---- popup khi chưa có tác vụ
        Item {
            anchors.fill: parent
            visible: app.compact
            RowLayout {
                anchors.centerIn: parent
                spacing: 14
                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: app.cLead
                    SequentialAnimation on opacity {
                        running: app.compact; loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
                ColumnLayout {
                    spacing: 3
                    T { text: app.popupModel; color: app.cLead; font.bold: true; font.pixelSize: 15 }
                    T {
                        text: "main session · pending" + (app.s?.effort ? " · " + app.s.effort : "")
                        color: app.muted
                    }
                }
            }
        }

        Rectangle {
            id: root
            anchors.fill: parent
            visible: !app.compact
            color: app.bg

            ColumnLayout {
                id: body
                anchors { fill: parent; margins: 14 }
                spacing: 10

                // ---- tiêu đề + chú thích
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    Repeater {
                        model: [
                            { c: app.cLead, t: (app.s?.model ?? "?") + " · lead" },
                            { c: app.cSwarm, t: "subagents · swarm" },
                            { c: app.cFork, t: "forks" },
                            { c: app.cAdv, t: "advisor" }
                        ]
                        RowLayout {
                            spacing: 6
                            Rectangle { width: 9; height: 9; color: modelData.c }
                            T { text: modelData.t; color: app.muted }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    T {
                        text: app.live ? "● live" : "○ idle"
                        color: app.live ? app.cFork : app.muted
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 18

                    // ---- cột trái: advisor
                    Box {
                        accent: app.cAdv
                        lit: app.advisorRunning
                        Layout.preferredWidth: 190
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors { fill: parent; margins: 10 }
                            spacing: 8
                            T { text: "ADVISOR"; color: app.cAdv; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                            T {
                                text: app.cap(app.advisorRuns.length ? app.advisorRuns[app.advisorRuns.length - 1].model : "sonnet") + " · on call"
                                color: app.cAdv; Layout.alignment: Qt.AlignHCenter
                            }
                            Mark { label: "before a plan"; on: app.advisorRuns.some(x => x.start < (app.swarm[0]?.start ?? 1e12)) }
                            T {
                                text: app.advisorRunning ? "reading the session…" : "reads the context,\nfiles and results"
                                color: app.muted; Layout.leftMargin: 14; wrapMode: Text.Wrap; Layout.fillWidth: true
                            }
                            T { text: "last advice:"; color: app.muted; Layout.leftMargin: 14 }
                            Repeater {
                                model: (app.s?.advisor?.last ?? []).length ? app.s.advisor.last : ["—"]
                                T {
                                    text: "» " + modelData; color: app.cAdv; font.bold: true
                                    Layout.leftMargin: 14; Layout.fillWidth: true
                                    wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                                }
                            }
                            RowLayout {
                                Layout.leftMargin: 14; Layout.fillWidth: true
                                T { text: "calls"; color: app.muted; Layout.fillWidth: true }
                                T { text: app.s?.advisor?.calls ?? 0 }
                            }
                            T {
                                visible: (app.s?.advisor?.at ?? 0) > 0
                                text: "last  " + app.ago(app.s?.advisor?.at ?? 0) + " ago"
                                color: app.muted; Layout.leftMargin: 14
                            }
                            T { text: "silent on every\nroutine turn"; color: app.muted; Layout.leftMargin: 14 }
                            Mark {
                                label: app.s?.repeatError ? "same error x2\n" + app.s.repeatError : "same error x2"
                                on: !!app.s?.repeatError; tint: app.cErr
                                Layout.fillWidth: true
                            }
                            T { text: "never writes\ncode itself.\n" + app.leadName + " applies\nthe advice."; color: app.muted; Layout.leftMargin: 14 }
                            Item { Layout.fillHeight: true }
                            Mark { label: "before done"; on: app.advisorRuns.some(x => x.start > Math.max(0, ...app.swarm.map(y => y.end || 1e12))) }
                        }
                    }

                    // ---- cột phải: lead → forks → swarm → lead
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Box {
                            accent: app.cLead
                            lit: app.phase === "lead" && app.s?.busy
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 260; implicitHeight: leadCol.implicitHeight + 16
                            ColumnLayout {
                                id: leadCol
                                anchors.centerIn: parent
                                spacing: 2
                                T { text: app.leadName + " · main session"; color: app.cLead; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                                T { text: "edits + runs tests"; Layout.alignment: Qt.AlignHCenter }
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    T { text: "effort"; color: app.muted }
                                    T { text: app.effortBlocks(app.s?.effort); color: app.cLead }
                                    T { text: app.s?.effort || "—" }
                                }
                                T {
                                    text: "tools " + (app.s?.tools ?? 0) + " · turn " + (app.s?.turns ?? 0)
                                    color: app.muted; Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        Wire { Layout.alignment: Qt.AlignHCenter; active: app.phase === "swarm"; tint: app.cLead }

                        Box {
                            accent: app.cFork
                            lit: app.forks.some(x => x.status === "running")
                            Layout.fillWidth: true
                            implicitHeight: forkCol.implicitHeight + 16
                            ColumnLayout {
                                id: forkCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                spacing: 3
                                RowLayout {
                                    T { text: "FORK LAYER"; color: app.cFork; font.bold: true }
                                    Item { Layout.fillWidth: true }
                                    T { text: "forks"; color: app.muted }
                                    T { text: app.forks.length; color: app.cFork; font.bold: true }
                                }
                                Repeater {
                                    model: [
                                        { k: "lead tool calls", v: app.s?.tools ?? 0 },
                                        { k: "swarm tool calls", v: app.swarm.reduce((n, x) => n + x.tools, 0) },
                                        { k: "agents done", v: app.swarm.filter(x => x.status === "done").length, of: app.swarm.length }
                                    ]
                                    RowLayout {
                                        Layout.fillWidth: true
                                        T { text: modelData.k; Layout.preferredWidth: 150 }
                                        Rectangle {
                                            Layout.fillWidth: true; height: 12; color: "#22262e"
                                            Rectangle {
                                                height: parent.height; color: app.cFork
                                                width: parent.width * Math.min(1, modelData.v / Math.max(1, modelData.of ?? Math.max(20, app.s?.tools ?? 0, app.swarm.reduce((n, x) => n + x.tools, 0))))
                                                Behavior on width { NumberAnimation { duration: 300 } }
                                            }
                                        }
                                        T { text: modelData.of !== undefined ? modelData.v + "/" + modelData.of : modelData.v; color: app.cFork; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                                    }
                                }
                            }
                        }

                        Wire { Layout.alignment: Qt.AlignHCenter; active: app.running > 0; tint: app.cSwarm }
                        T {
                            text: "delegate to subagents" + (app.swarm.length ? " · " + [...new Set(app.swarm.map(x => x.model))].join(", ") : "")
                            Layout.alignment: Qt.AlignHCenter
                            color: app.cSwarm
                        }
                        Wire { Layout.alignment: Qt.AlignHCenter; active: app.running > 0; tint: app.cSwarm }

                        // ---- swarm
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Repeater {
                                model: app.swarm.slice(-4)
                                Box {
                                    required property var modelData
                                    readonly property bool run: modelData.status === "running"
                                    accent: app.cSwarm
                                    lit: run
                                    Layout.fillWidth: true
                                    implicitHeight: card.implicitHeight + 14
                                    ColumnLayout {
                                        id: card
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7 }
                                        spacing: 3
                                        T { text: modelData.type; font.bold: true; Layout.alignment: Qt.AlignHCenter; elide: Text.ElideRight; Layout.maximumWidth: parent.width }
                                        T { text: app.cap(modelData.model); color: app.cSwarm; Layout.alignment: Qt.AlignHCenter }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Rectangle {
                                                Layout.fillWidth: true; height: 12; color: "#22262e"
                                                Rectangle {
                                                    height: parent.height; color: app.cSwarm
                                                    width: parent.width * (modelData.status === "done" ? 1 : Math.min(0.95, modelData.tools / app.maxTools))
                                                    Behavior on width { NumberAnimation { duration: 300 } }
                                                }
                                            }
                                            T { text: modelData.tools; color: app.muted }
                                        }
                                        T {
                                            text: modelData.desc || modelData.tool || "…"
                                            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                        }
                                        T {
                                            text: run ? "◐ running " + app.ago(modelData.start) + (modelData.tool ? " · " + modelData.tool : "")
                                                      : "✓ done " + Math.round(modelData.end - modelData.start) + "s"
                                            color: run ? app.fg : app.cFork
                                            Layout.alignment: Qt.AlignHCenter
                                            elide: Text.ElideRight; Layout.maximumWidth: parent.width
                                        }
                                    }
                                }
                            }
                        }
                        T {
                            visible: app.swarm.length === 0
                            text: "no subagents this turn"
                            color: app.muted; Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 6; Layout.bottomMargin: 6
                        }
                        T {
                            visible: app.swarm.length > 4
                            text: "+" + (app.swarm.length - 4) + " earlier"
                            color: app.muted; Layout.alignment: Qt.AlignHCenter
                        }

                        Wire { Layout.alignment: Qt.AlignHCenter; active: app.phase === "review"; tint: app.cLead }

                        Box {
                            accent: app.cLead
                            lit: app.phase === "review" || app.phase === "done"
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 260; implicitHeight: 48
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2
                                T { text: "back to " + app.leadName + " · lead"; color: app.cLead; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                                T {
                                    text: app.phase === "done" ? "✓ finished " + app.ago(app.s?.doneAt ?? app.now) + " ago" : "review + verify"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
