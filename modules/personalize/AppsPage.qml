import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Aplicaciones: mostrar u ocultar cada app en el menú de apps, sin editar los .desktop
// (el modo de Arch es poner NoDisplay=true en el archivo; aquí se guarda en settings.json).
ColumnLayout {
    id: page

    spacing: 16

    property string filter: "all"     // all | shown | hidden
    readonly property string query: Apps.normalize(searchIn.text.trim())
    readonly property var list: Apps.everything.filter(a => {
        const vis = Apps.isVisible(a);
        if (page.filter === "shown" && !vis) return false;
        if (page.filter === "hidden" && vis) return false;
        if (!page.query) return true;
        return Apps.normalize(a.name).includes(page.query) || Apps.normalize(a.id).includes(page.query)
            || Apps.normalize(Apps.packages[a.id] ?? "").includes(page.query);
    })
    readonly property int hiddenCount: Apps.everything.length - Apps.all.length

    Component.onCompleted: Apps.loadPackages()   // por si se instaló algo con el shell abierto

    Group {
        title: I18n.t("Aplicaciones en el menú")
        help: I18n.t("Elige qué apps aparecen en el menú de apps. También puedes mostrar las que el paquete oculta (NoDisplay). No se modifica ningún archivo del sistema.")
        icon: "apps"

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40; radius: 20
                color: Theme.surfaceHigh
                border.width: searchIn.activeFocus ? 2 : 1
                border.color: searchIn.activeFocus ? Theme.primary : Theme.alpha(Theme.fg, 0.1)
                Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "search"; size: 18; color: Theme.fgMuted }
                TextInput {
                    id: searchIn
                    anchors.fill: parent
                    anchors.leftMargin: 42; anchors.rightMargin: 16
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font; font.pixelSize: Theme.textNormal
                    color: Theme.fg
                    clip: true
                    Txt { anchors.verticalCenter: parent.verticalCenter; visible: !searchIn.text && !searchIn.activeFocus; text: I18n.t("Buscar por nombre o paquete…"); color: Theme.fgMuted }
                }
            }
            Segmented {
                options: [{ v: "all", t: I18n.t("Todas"), i: "apps" },
                          { v: "shown", t: I18n.t("Visibles"), i: "visibility" },
                          { v: "hidden", t: I18n.t("Ocultas"), i: "visibility_off" }]
                value: page.filter
                onPicked: v => page.filter = v
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Txt {
                Layout.fillWidth: true
                text: Apps.all.length + I18n.t(" visibles · ") + page.hiddenCount + I18n.t(" ocultas")
                color: Theme.fgMuted
                font.pixelSize: Theme.textSmall
            }
            PillButton {
                text: I18n.t("Restablecer")
                icon: "restart_alt"
                visible: (Settings.apps.hidden ?? []).length + (Settings.apps.shown ?? []).length > 0
                onClicked: Apps.resetVisibility()
            }
        }

        Repeater {
            model: page.list
            RowLayout {
                id: row
                required property var modelData
                readonly property bool vis: Apps.isVisible(modelData)
                readonly property string pkg: Apps.packages[modelData.id] ?? ""
                Layout.fillWidth: true
                spacing: 12
                opacity: vis ? 1 : 0.6

                AppIcon { name: row.modelData.icon; size: 32 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    RowLayout {
                        spacing: 6
                        Txt { text: row.modelData.name; font.weight: Font.DemiBold }
                        Rectangle {
                            visible: row.modelData.noDisplay
                            implicitWidth: ndT.implicitWidth + 12; implicitHeight: 18; radius: 9
                            color: Theme.alpha(Theme.fg, 0.08)
                            Txt { id: ndT; anchors.centerIn: parent; text: I18n.t("oculta por el paquete"); font.pixelSize: 10; color: Theme.fgMuted }
                        }
                        Rectangle {
                            visible: Apps.isOverridden(row.modelData)
                            implicitWidth: ovT.implicitWidth + 12; implicitHeight: 18; radius: 9
                            color: Theme.alpha(Theme.primary, 0.16)
                            Txt { id: ovT; anchors.centerIn: parent; text: I18n.t("cambiada por ti"); font.pixelSize: 10; color: Theme.primary }
                        }
                    }
                    Txt {
                        Layout.fillWidth: true
                        text: (row.pkg === "flatpak" ? "Flatpak" : row.pkg === "local" ? I18n.t("Instalada por ti (~/.local)")
                               : row.pkg ? I18n.t("Paquete: ") + row.pkg : Apps.packagesLoaded ? I18n.t("Sin paquete") : "…")
                              + "  ·  " + row.modelData.id
                        color: Theme.fgMuted
                        font.pixelSize: Theme.textSmall
                        elide: Text.ElideRight
                    }
                }
                Toggle {
                    checked: row.vis
                    onToggled: c => Apps.setVisible(row.modelData, c)
                }
            }
        }

        Txt {
            visible: page.list.length === 0
            text: I18n.t("No hay apps que coincidan.")
            color: Theme.fgMuted
        }
    }
}
