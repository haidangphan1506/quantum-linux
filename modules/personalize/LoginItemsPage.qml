import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// General → Elementos de inicio (como «Ítems de inicio» de macOS): las apps que se
// abren solas al iniciar sesión. Se agregan con + y se quitan con −.
ColumnLayout {
    id: page
    spacing: 16

    readonly property var login: Settings.apps.login ?? []
    property bool adding: false
    property string query: ""

    function setLogin(list: var): void { Settings.set("apps", "login", list); }

    Group {
        title: I18n.t("Abrir al iniciar sesión")
        help: I18n.t("Estas apps se abren solas cada vez que inicias sesión.")
        Repeater {
            model: page.login
            OptionRow {
                required property string modelData
                readonly property var app: Apps.entry(modelData)
                title: app?.name ?? modelData
                appIcon: app?.icon || "application-x-executable"
                IconButton {
                    icon: "remove"
                    iconSize: 16; implicitWidth: 28; implicitHeight: 28
                    onClicked: page.setLogin(page.login.filter(x => x !== modelData))
                }
            }
        }
        OptionRow {
            visible: page.login.length === 0
            title: I18n.t("Ninguna app se abre al iniciar sesión.")
        }
        OptionRow {
            title: ""
            PillButton {
                text: page.adding ? I18n.t("Listo") : I18n.t("Agregar app…")
                icon: page.adding ? "check" : "add"
                implicitHeight: 28
                onClicked: { page.adding = !page.adding; page.query = ""; }
            }
        }
    }

    Group {
        visible: page.adding
        title: I18n.t("Elige una app")
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 6
            implicitHeight: 30
            radius: 8
            color: Theme.alpha(Theme.fg, 0.07)
            TextInput {
                id: q
                anchors.fill: parent
                anchors.leftMargin: 10; anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.font; font.pixelSize: Theme.textNormal
                color: Theme.fg
                clip: true
                onTextChanged: page.query = text
                Txt { anchors.verticalCenter: parent.verticalCenter; visible: !q.text; text: I18n.t("Buscar"); color: Theme.fgMuted }
            }
        }
        Repeater {
            model: (page.query ? Apps.search(page.query) : Apps.all).filter(a => !page.login.includes(a.id)).slice(0, 12)
            OptionRow {
                required property var modelData
                title: modelData.name
                help: modelData.comment || ""
                appIcon: modelData.icon || "application-x-executable"
                PillButton {
                    text: I18n.t("Agregar"); implicitHeight: 28
                    onClicked: page.setLogin(page.login.concat([modelData.id]))
                }
            }
        }
    }
}
