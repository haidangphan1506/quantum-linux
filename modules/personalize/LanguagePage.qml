import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Idioma de la interfaz: Tiếng Việt / English (Settings.ui.lang, ver services/I18n.qml).
ColumnLayout {
    id: page

    spacing: 16

    Group {
        title: I18n.t("Idioma del escritorio")
        help: I18n.t("Se aplica al instante en todo Quantum Shell.")
        icon: "translate"
        Segmented {
            options: I18n.languages
            value: I18n.lang
            onPicked: v => I18n.setLang(v)
        }
    }
}
