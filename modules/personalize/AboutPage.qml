import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// General → Acerca de (como «Acerca de este Mac» en Ajustes del Sistema de macOS):
// el equipo dibujado con su nombre y año, una tabla con nombre, chip, gráfica y memoria,
// el sistema con su versión, las pantallas y el almacenamiento.
ColumnLayout {
    id: page
    spacing: 16

    property var info: ({})
    Component.onCompleted: { SysInfo.active = true; probe.running = true; mons.running = true; }
    Component.onDestruction: SysInfo.active = false

    Process {
        id: probe
        command: ["sh", "-c", `. /etc/os-release
echo "os=$NAME"
echo "osver=$VERSION_ID$BUILD_ID"
echo "kernel=$(uname -r)"
echo "host=$(uname -n)"
# tên thương mại: Lenovo guarda el modelo en product_family/version (product_name es un código)
fam=$(cat /sys/class/dmi/id/product_family 2>/dev/null); pv=$(cat /sys/class/dmi/id/product_version 2>/dev/null)
pn=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
case "$fam" in ""|"Default string"|"To be filled"*) fam="$pv";; esac
case "$fam" in ""|"Default string"|"To be filled"*|"None") fam="$pn";; esac
echo "model=$fam"
echo "vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)"
echo "year=$(cat /sys/class/dmi/id/bios_date 2>/dev/null | grep -o '[0-9]\\{4\\}$')"
echo "chassis=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//; s/([^)]*)//g; s/ CPU//; s/ @.*//')"
echo "ver=$(pacman -Q quantum-shell 2>/dev/null | cut -d' ' -f2)"
echo "gpu=$(lspci -mm 2>/dev/null | grep -E '"(VGA|3D|Display)' | head -1 | awk -F'"' '{print $6}' | sed 's/\[//; s/\]//')"
echo "user=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const l of text.split("\n")) {
                    const i = l.indexOf("=");
                    if (i > 0) o[l.slice(0, i)] = l.slice(i + 1).trim();
                }
                page.info = o;
            }
        }
    }

    property var monitors: []
    Process {
        id: mons
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { page.monitors = JSON.parse(text); } catch (e) {} } }
    }

    // portátil (tipos de chasis 8-14, 31, 32) o sobremesa
    readonly property bool laptop: [8, 9, 10, 14, 31, 32].indexOf(Number(info.chassis || 0)) >= 0

    // ------------------------------------------------------------ equipo
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 4
        Item { Layout.fillWidth: true }    // para que el bloque ocupe todo el ancho y se centre
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 170
            implicitHeight: 118
            Rectangle {
                id: screenRect
                width: 150; height: 96
                anchors.horizontalCenter: parent.horizontalCenter
                radius: 8
                color: "#1c1c1e"
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 5
                    radius: 4
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#64a8ff" }
                        GradientStop { position: 1; color: "#7b5cff" }
                    }
                }
            }
            Rectangle {
                visible: !page.laptop
                anchors.top: screenRect.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: 34; height: 16
                color: "#c7c7cc"
            }
            Rectangle {
                anchors.top: screenRect.bottom
                anchors.topMargin: page.laptop ? 0 : 16
                anchors.horizontalCenter: parent.horizontalCenter
                width: page.laptop ? 170 : 56; height: page.laptop ? 8 : 5
                radius: 4
                color: "#c7c7cc"
            }
        }
        Txt {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            text: page.info.model || page.info.host || "—"
            font.pixelSize: Theme.textNormal + 10
            font.weight: Font.Bold
        }
        Txt {
            Layout.alignment: Qt.AlignHCenter
            visible: !!page.info.year || !!page.info.vendor
            text: [page.info.vendor, page.info.year].filter(x => !!x).join(" · ")
            color: Theme.fgMuted
        }
    }

    Group {
        OptionRow { title: I18n.t("Nombre"); Txt { text: page.info.host || "—"; color: Theme.fgMuted } }
        OptionRow { title: I18n.t("Procesador"); Txt { text: page.info.cpu || "—"; color: Theme.fgMuted; elide: Text.ElideRight; width: Math.min(implicitWidth, 380) } }
        OptionRow { visible: !!page.info.gpu; title: I18n.t("Gráficos"); Txt { text: page.info.gpu || ""; color: Theme.fgMuted; elide: Text.ElideRight; width: Math.min(implicitWidth, 380) } }
        OptionRow { title: I18n.t("Memoria"); Txt { text: SysInfo.ramTotalGb > 0 ? Math.round(SysInfo.ramTotalGb) + " GB" : "—"; color: Theme.fgMuted } }
        OptionRow { visible: !!page.info.user; title: I18n.t("Usuario"); Txt { text: page.info.user || ""; color: Theme.fgMuted } }
    }

    // ------------------------------------------------------------ sistema
    Group {
        OptionRow {
            title: page.info.os || "Quantum Linux"
            help: I18n.t("Versión") + " " + (page.info.osver || page.info.ver || "—") + " · Linux " + (page.info.kernel || "")
            icon: "deployed_code"
            iconColor: "#7b5cff"
        }
        NavRow {
            title: I18n.t("Actualización de software")
            value: Updates.count > 0 ? "" : I18n.t("Al día")
            badge: Updates.count
            onClicked: Shell.settingsGo("update")
        }
    }

    // ------------------------------------------------------------ pantallas
    Group {
        title: I18n.t("Pantallas")
        Repeater {
            model: page.monitors
            OptionRow {
                required property var modelData
                title: modelData.description || modelData.name
                help: modelData.width + " × " + modelData.height + " · " + Math.round(modelData.refreshRate) + " Hz" + (modelData.scale !== 1 ? " · " + I18n.t("escala") + " " + modelData.scale : "")
                icon: "desktop_windows"
                PillButton { text: I18n.t("Ajustes de pantalla…"); implicitHeight: 28; onClicked: Shell.settingsGo("display") }
            }
        }
    }

    // ------------------------------------------------------------ almacenamiento
    Group {
        title: I18n.t("Almacenamiento")
        NavRow {
            title: I18n.t("Disco del sistema")
            help: SysInfo.diskTotalGb > 0 ? Math.round(SysInfo.diskTotalGb - SysInfo.diskUsedGb) + " GB " + I18n.t("disponibles de") + " " + Math.round(SysInfo.diskTotalGb) + " GB" : "—"
            icon: "hard_drive"
            iconColor: "#8E8E93"
            onClicked: Shell.settingsGo("storage")
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        Layout.topMargin: 4
        PillButton { text: I18n.t("Informe del sistema…"); implicitHeight: 30; onClicked: Shell.openAbout() }
    }
}
