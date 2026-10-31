import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import qs.services
import qs.components

// Música: lo que suena, con anterior / pausa / siguiente.
LockCard {
    id: card
    implicitHeight: 230
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    Image {
        parent: card
        anchors.fill: parent
        visible: !!card.player?.trackArtUrl
        source: card.player?.trackArtUrl ?? ""
        fillMode: Image.PreserveAspectCrop
        opacity: 0.45
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 0.6; blurMax: 32 }
    }
    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: 6
        visible: !!card.player
        Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: card.player?.trackTitle || "Sin título"; font.pixelSize: 20; font.weight: Font.DemiBold; color: Theme.primary; elide: Text.ElideRight }
        Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: card.player?.trackArtist || ""; color: Theme.fg }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 22
            spacing: 4
            visible: card.player?.isPlaying ?? false
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    anchors.bottom: parent.bottom
                    width: 5; radius: 2.5
                    color: Theme.primary
                    height: 6
                    SequentialAnimation on height {
                        loops: Animation.Infinite
                        running: card.player?.isPlaying ?? false
                        NumberAnimation { to: 8 + (index * 7 % 13); duration: 260 + index * 70; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 4; duration: 300 + index * 50; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
        Item { width: 1; height: 8 }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Repeater {
                model: [
                    { i: "skip_previous", big: false, run: () => card.player.previous() },
                    { i: card.player?.isPlaying ? "pause" : "play_arrow", big: true, run: () => card.player.togglePlaying() },
                    { i: "skip_next", big: false, run: () => card.player.next() },
                ]
                Rectangle {
                    required property var modelData
                    width: modelData.big ? 84 : 48; height: 48; radius: 24
                    color: modelData.big ? Theme.primary : Qt.rgba(1, 1, 1, 0.1)
                    Icon { anchors.centerIn: parent; text: parent.modelData.i; size: 26; fill: 1; color: parent.modelData.big ? Theme.primaryFg : Theme.fg }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.modelData.run() }
                }
            }
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: 8
        visible: !card.player
        Icon { anchors.horizontalCenter: parent.horizontalCenter; text: "music_off"; size: 44; color: Theme.fgMuted }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Nada sonando"; color: Theme.fgMuted }
    }
}
