import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.components

// Ventana «Acerca de este equipo» con la información del sistema.
Scope {
    // ------------------------------------------------------ Acerca de este PC
    LazyLoader {
        active: Shell.aboutOpen

        FloatingWindow {
            id: win

            title: "Acerca de este equipo"
            implicitWidth: 460
            implicitHeight: 600
            minimumSize: Qt.size(400, 440)
            color: Theme.surface
            visible: true
            onVisibleChanged: if (!visible) Shell.aboutOpen = false

            property var info: ({})
            Component.onCompleted: { SysInfo.active = true; probe.running = true; }
            Component.onDestruction: SysInfo.active = false

            Shortcut { sequence: "Escape"; onActivated: Shell.aboutOpen = false }

            // Datos fijos del equipo, una sola vez al abrir
            Process {
                id: probe
                command: ["sh", "-c", `. /etc/os-release
echo "os=$PRETTY_NAME"
echo "ver=$(pacman -Q quantum-shell 2>/dev/null | cut -d' ' -f2)"
echo "kernel=$(uname -r)"
echo "host=$(uname -n)"
echo "model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
echo "cores=$(nproc)"
echo "gpu=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | sed 's/^[^ ]* //; s/^[^:]*: //')"
echo "up=$(cut -d' ' -f1 /proc/uptime)"
echo "session=$XDG_SESSION_TYPE"`]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const o = {};
                        for (const l of text.split("\n")) {
                            const i = l.indexOf("=");
                            if (i > 0) o[l.slice(0, i)] = l.slice(i + 1).trim();
                        }
                        win.info = o;
                    }
                }
            }

            function uptime(): string {
                const s = Math.floor(Number(info.up || 0));
                const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                return (d ? d + " d " : "") + (h ? h + " h " : "") + m + " min";
            }
            function gb(v: real): string { return v.toFixed(1).replace(".", ",") + " GB"; }

            readonly property var rows: [
                { k: "Equipo", v: info.model || info.host || "—" },
                { k: "Nombre", v: info.host || "—" },
                { k: "Procesador", v: (info.cpu || "—") + (info.cores ? " (" + info.cores + " hilos)" : "") },
                { k: "Gráficos", v: info.gpu || "—" },
                { k: "Memoria", v: SysInfo.ramTotalGb > 0 ? gb(SysInfo.ramUsedGb) + " usados de " + gb(SysInfo.ramTotalGb) : "—" },
                { k: "Almacenamiento", v: SysInfo.diskTotalGb > 0 ? Math.round(SysInfo.diskUsedGb) + " GB usados de " + Math.round(SysInfo.diskTotalGb) + " GB" : "—" },
                { k: "Kernel", v: info.kernel || "—" },
                { k: "Sesión", v: info.session ? (info.session === "wayland" ? "Wayland" : info.session) : "—" },
                { k: "Encendido hace", v: info.up ? uptime() : "—" },
            ]

            function copyText(): string {
                return "Quantum Linux" + (info.ver ? " " + info.ver : "") + "\n" + rows.map(r => r.k + ": " + r.v).join("\n");
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 0

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    source: Quickshell.shellDir + "/assets/quantum-mark.svg"
                    sourceSize: Qt.size(128, 128)
                    smooth: true
                }
                Txt {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    text: "Quantum Linux"
                    font.pixelSize: Theme.textTitle + 4
                    font.weight: Font.Black
                }
                Txt {
                    Layout.alignment: Qt.AlignHCenter
                    text: (win.info.os || "") + (win.info.ver ? " · versión " + win.info.ver : "")
                    color: Theme.fgMuted
                    font.pixelSize: Theme.textSmall
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    implicitHeight: list.implicitHeight + 16
                    radius: Theme.radius
                    color: Theme.surfaceLow

                    ColumnLayout {
                        id: list
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 0

                        Repeater {
                            model: win.rows
                            RowLayout {
                                id: line
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 14
                                Item { implicitWidth: 0; implicitHeight: 32 }
                                Txt {
                                    Layout.preferredWidth: 130
                                    text: line.modelData.k
                                    color: Theme.fgMuted
                                    font.weight: Font.Medium
                                    leftPadding: 8
                                }
                                Txt {
                                    Layout.fillWidth: true
                                    text: line.modelData.v
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    PillButton {
                        primary: true
                        icon: "content_copy"
                        text: "Copiar información"
                        onClicked: Quickshell.execDetached(["wl-copy", win.copyText()])
                    }
                }
            }
        }
    }
}
