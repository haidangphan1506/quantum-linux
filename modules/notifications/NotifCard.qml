import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.services
import qs.components

// Tarjeta de notificación (emergente o en el historial).
Rectangle {
    id: root

    required property Notification notif
    property bool popup: false
    // Muchas apps (y notify-send -i) mandan el ícono como "imagen": entonces
    // se usa como ícono y no como imagen grande.
    readonly property string iconSource: notif.appIcon ? Quickshell.iconPath(notif.appIcon, true) : notif.image
    readonly property bool bigImage: notif.appIcon !== "" && notif.image !== ""

    implicitHeight: content.implicitHeight + 24
    radius: Theme.radius
    color: popup ? Theme.alpha(Theme.surface, 0.94) : Theme.surfaceHigh
    border.width: popup ? 1 : 0
    border.color: notif.urgency === NotificationUrgency.Critical ? Theme.error : Theme.alpha(Theme.fg, 0.08)

    // Clic en la tarjeta: acción por defecto (si existe)
    MouseArea {
        anchors.fill: parent
        onClicked: {
            const def = root.notif.actions.find(a => a.identifier === "default");
            if (def)
                def.invoke();
            else if (root.popup)
                Notifs.dismissPopup(root.notif);
        }
    }

    RowLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12

        // Ícono de la app
        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 40
            implicitHeight: 40
            radius: 12
            color: Theme.alpha(Theme.primary, 0.14)

            IconImage {
                id: appIcon
                anchors.centerIn: parent
                implicitSize: 26
                visible: status === Image.Ready
                source: root.iconSource
            }
            Icon {
                anchors.centerIn: parent
                visible: appIcon.status !== Image.Ready
                text: "notifications"
                color: Theme.primary
                fill: 1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                Txt {
                    Layout.fillWidth: true
                    text: root.notif.summary || root.notif.appName
                    font.weight: Font.DemiBold
                }
                Txt {
                    text: root.notif.appName
                    visible: root.notif.summary !== "" && text !== ""
                    font.pixelSize: Theme.textSmall
                    color: Theme.fgMuted
                }
                IconButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    icon: "close"
                    iconSize: 16
                    onClicked: root.notif.dismiss()
                }
            }

            Txt {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.notif.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: root.popup ? 3 : 5
                color: Theme.fgMuted
                font.pixelSize: Theme.textSmall + 1
                onLinkActivated: url => Qt.openUrlExternally(url)
            }

            Image {
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 140 : 0
                visible: root.bigImage && status === Image.Ready
                source: root.notif.image
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            // Botones de acción
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: actionsRepeater.count > 0
                spacing: 6

                Repeater {
                    id: actionsRepeater
                    model: root.notif.actions.filter(a => a.identifier !== "default")

                    Rectangle {
                        required property NotificationAction modelData
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: height / 2
                        color: actArea.containsMouse ? Theme.primary : Theme.surfaceHighest
                        Txt {
                            anchors.centerIn: parent
                            text: parent.modelData.text
                            font.pixelSize: Theme.textSmall
                            font.weight: Font.DemiBold
                            color: actArea.containsMouse ? Theme.primaryFg : Theme.fg
                        }
                        MouseArea {
                            id: actArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.modelData.invoke()
                        }
                    }
                }
            }
        }
    }
}
