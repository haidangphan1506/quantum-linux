import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Fila pequeña de detalle del popup de Claude (ClaudeMeter): etiqueta · valor
RowLayout {
    id: row

    property string label
    property string value
    property color valueColor: Theme.fg

    Layout.fillWidth: true
    spacing: 6

    Txt { Layout.fillWidth: true; text: row.label; font.pixelSize: 11; color: Theme.fgMuted; elide: Text.ElideRight }
    Txt { text: row.value; font.pixelSize: 11; font.features: { "tnum": 1 }; color: row.valueColor }
}
