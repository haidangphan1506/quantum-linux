import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Barra y dock: distribución, estilo, alineación, tamaño y qué se muestra.
ColumnLayout {
    id: page

    spacing: 16
    readonly property bool single: Settings.layout.style === "single"

    // Dibujo simple de una distribución de barras.
    component LayoutArt: Rectangle {
        id: art
        property bool single: false
        radius: Theme.radius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.alpha(Theme.primaryContainer, 0.55) }
            GradientStop { position: 1; color: Theme.alpha(Theme.primary, 0.3) }
        }
        Rectangle {
            visible: !art.single
            x: 8; y: 7; width: parent.width - 16; height: 12; radius: 6
            color: Theme.alpha(Theme.surface, 0.85)
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: art.single ? 0 : 7
            anchors.horizontalCenter: parent.horizontalCenter
            width: art.single ? parent.width : parent.width * 0.42
            height: 16
            radius: art.single ? 0 : 8
            color: Theme.alpha(Theme.surface, 0.9)
            Row {
                anchors.centerIn: parent
                spacing: 5
                Repeater { model: 5; Rectangle { required property int index; width: 8; height: 8; radius: 2; color: index === 0 ? Theme.primary : Theme.alpha(Theme.fg, 0.5) } }
            }
            Rectangle {
                visible: art.single
                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 4; radius: 2; color: Theme.alpha(Theme.fg, 0.6)
            }
        }
    }

    // Las dos formas de Quantum Shell: también aquí, que es donde se busca al querer cambiar la barra
    Group {
        title: "Quantum Shell"
        help: Serp.on ? "Serpantium: barra de píldoras arriba, paneles oscuros y tonos rosados."
                      : "Caelestial: barra arriba, dock y paneles de vidrio."
        icon: "dashboard"
        Segmented {
            options: [{ v: "caelestial", t: "Caelestial", i: "blur_on" }, { v: "serpantium", t: "Serpantium", i: "terminal" }]
            value: Settings.ui.shell
            onPicked: v => Serp.choose(v, false)
        }
    }

    // Serpantium: dónde van las apps abiertas y fijadas
    Group {
        visible: Serp.on
        title: "Tus apps"
        help: "Dónde aparecen las apps fijadas y las que tienes abiertas."
        icon: "apps"
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            ChoiceCard {
                title: "En la barra de arriba"
                help: "Íconos chicos junto al buscador. Más espacio para tus ventanas."
                selected: Settings.ui.serpApps !== "dock"
                previewHeight: 96
                onClicked: Settings.setUi("serpApps", "bar")
                SerpArt { anchors.fill: parent; dock: false }
            }
            ChoiceCard {
                title: "Dock abajo"
                help: "Una barra de apps abajo, como en Windows: fijar, ordenar arrastrando y ver ventanas."
                selected: Settings.ui.serpApps === "dock"
                previewHeight: 96
                onClicked: Settings.setUi("serpApps", "dock")
                SerpArt { anchors.fill: parent; dock: true }
            }
        }
    }

    component SerpArt: Rectangle {
        id: sa
        property bool dock: false
        radius: Theme.radius
        color: "#B86A97"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height * 0.45; radius: Theme.radius; color: "#5C2550" }
        Row {
            x: 8; y: 8; spacing: 4
            Repeater { model: sa.dock ? [14, 14] : [14, 14, 46]; Rectangle { required property var modelData; width: modelData; height: 12; radius: 4; color: "#1F171D" } }
        }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 8; width: 40; height: 12; radius: 4; color: "#1F171D" }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 8; y: 8; spacing: 4
            Repeater { model: [24, 18, 12]; Rectangle { required property var modelData; width: modelData; height: 12; radius: 4; color: "#1F171D" } }
        }
        Rectangle {
            visible: sa.dock
            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            width: 110; height: 22; radius: 8; color: "#1F171D"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
            Row { anchors.centerIn: parent; spacing: 5; Repeater { model: 5; Rectangle { width: 14; height: 14; radius: 4; color: index === 0 ? "#F4A7C9" : Qt.rgba(1, 1, 1, 0.35) } } }
        }
    }

    Group {
        visible: !Serp.on
        title: "Distribución"
        help: "Cómo se reparten las barras en la pantalla."
        icon: "view_quilt"
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            ChoiceCard {
                title: "Barra arriba + barra de tareas"
                help: "Como viene Quantum: hora y estado arriba, apps abajo."
                selected: !page.single
                previewHeight: 96
                onClicked: Settings.setPath("layout.style", "split")
                LayoutArt { anchors.fill: parent; single: false }
            }
            ChoiceCard {
                title: "Una sola barra abajo"
                help: "Como en Windows: apps, bandeja y hora en una barra."
                selected: page.single
                previewHeight: 96
                onClicked: Settings.setPath("layout.style", "single")
                LayoutArt { anchors.fill: parent; single: true }
            }
        }
    }

    Group {
        visible: !Serp.on || Settings.ui.serpApps === "dock"
        title: Serp.on ? "Dock" : "Barra de tareas"
        help: Serp.on ? "La barra de apps de abajo: fijadas y abiertas." : "La barra de abajo, donde están Inicio y tus apps."
        icon: "dock_to_bottom"

        OptionRow {
            visible: !Serp.on
            title: "Estilo"
            help: "Flotante deja un espacio alrededor; pegada ocupa todo el borde."
            Segmented {
                options: [{ v: true, t: "Flotante", i: "rounded_corner" }, { v: false, t: "Pegada", i: "border_bottom" }]
                value: Settings.dock.floating
                onPicked: v => Settings.set("dock", "floating", v)
            }
        }
        OptionRow {
            visible: !Serp.on
            title: "Posición de las apps"
            help: page.single || !Settings.dock.floating ? "" : "Con la barra flotante sola, las apps siempre van al centro."
            Segmented {
                options: [{ v: "center", t: "Al centro", i: "format_align_center" }, { v: "left", t: "A la izquierda", i: "format_align_left" }]
                value: Settings.dock.align
                onPicked: v => Settings.set("dock", "align", v)
            }
        }
        OptionRow {
            title: "Tamaño"
            Segmented {
                options: [{ v: "small", t: "Pequeña" }, { v: "medium", t: "Mediana" }, { v: "large", t: "Grande" }]
                value: Settings.dock.size
                onPicked: v => Settings.set("dock", "size", v)
            }
        }
        OptionRow {
            title: "Ocultar automáticamente"
            help: "La barra se esconde y aparece al llevar el mouse al borde de abajo."
            Toggle { checked: Settings.dock.autohide; onToggled: c => Settings.set("dock", "autohide", c) }
        }
    }

    Group {
        visible: !Serp.on
        title: "Botones de la barra"
        help: "Qué se muestra junto a tus apps."
        icon: "apps"
        advanced: true
        OptionRow {
            title: "Botón de Inicio"
            icon: "grid_view"
            Toggle { checked: Settings.dock.showStart; onToggled: c => Settings.set("dock", "showStart", c) }
        }
        OptionRow {
            title: "Botón de búsqueda"
            icon: "search"
            Toggle { checked: Settings.dock.showSearch; onToggled: c => Settings.set("dock", "showSearch", c) }
        }
        OptionRow {
            title: "Aviso de actualizaciones"
            icon: "system_update_alt"
            help: "Aparece solo cuando hay algo nuevo para instalar."
            Toggle { checked: Settings.dock.showUpdates; onToggled: c => Settings.set("dock", "showUpdates", c) }
        }
        OptionRow {
            title: "Bandeja del sistema"
            icon: "notifications"
            help: "Los íconos de las apps en segundo plano (Discord, Steam, etc.)."
            Toggle { checked: Settings.dock.showTray; onToggled: c => Settings.set("dock", "showTray", c) }
        }
    }

    Group {
        visible: !Serp.on
        title: "Barra superior"
        help: page.single ? "No se usa con «Una sola barra abajo»." : "La barra de arriba, con la app activa, la hora y el estado."
        icon: "top_panel_open"
        advanced: true
        enabled: !page.single
        opacity: page.single ? 0.5 : 1
        OptionRow {
            title: "Estilo"
            Segmented {
                options: [{ v: true, t: "Flotante" }, { v: false, t: "Pegada" }]
                value: Settings.layout.topBar.floating
                onPicked: v => Settings.setPath("layout.topBar.floating", v)
            }
        }
        OptionRow {
            title: "Mostrar la app activa"
            help: "El nombre y el ícono de la ventana que estás usando, a la izquierda."
            Toggle { checked: Settings.layout.topBar.showApp; onToggled: c => Settings.setPath("layout.topBar.showApp", c) }
        }
    }

    Group {
        visible: !Serp.on
        title: "Reloj"
        icon: "schedule"
        advanced: true
        OptionRow {
            title: "Formato"
            Segmented {
                options: [{ v: true, t: "24 horas" }, { v: false, t: "12 horas (a. m./p. m.)" }]
                value: Settings.clock.format24h
                onPicked: v => Settings.set("clock", "format24h", v)
            }
        }
        OptionRow {
            title: "Mostrar la fecha"
            Toggle { checked: Settings.clock.showDate; onToggled: c => Settings.set("clock", "showDate", c) }
        }
        OptionRow {
            title: "Mostrar los segundos"
            Toggle { checked: Settings.clock.showSeconds; onToggled: c => Settings.set("clock", "showSeconds", c) }
        }
    }
}
