import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Asistente Quantum (Super + H): chat con una IA que corre en tu PC (Ollama).
// Panel lateral a la derecha. Si la IA no está instalada, ofrece instalarla.
Scope {
    LazyLoader {
        active: Shell.aiOpen

        PanelWindow {
            id: win

            screen: Wm.screen
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quantum-panel"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            anchors { top: true; bottom: true; right: true }
            margins { top: 62; bottom: 90; right: 10 }
            implicitWidth: 480
            exclusionMode: ExclusionMode.Normal
            color: "transparent"

            property real progress: 0
            NumberAnimation on progress { from: 0; to: 1; duration: Theme.animSlow; easing.type: Easing.OutCubic }
            Component.onCompleted: Ai.check()

            // modelos para instalar si todavía no hay IA
            readonly property var tiers: [
                { m: "gemma3:1b", t: "Ligero", h: "0,8 GB · PCs con 4 GB de RAM" },
                { m: "gemma3:4b", t: "Equilibrado", h: "3,4 GB · 8 GB de RAM" },
                { m: "qwen3:8b", t: "Avanzado", h: "5,2 GB · 16 GB de RAM o buena gráfica" },
            ]
            property string tier: "gemma3:4b"

            Card {
                id: card
                anchors.fill: parent
                opacity: win.progress
                transform: Translate { x: (1 - win.progress) * 60 }
                focus: true
                Keys.onEscapePressed: Shell.aiOpen = false

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    // encabezado
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            implicitWidth: 42; implicitHeight: 42; radius: 14
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Theme.brandCyan }
                                GradientStop { position: 0.5; color: Theme.brandIndigo }
                                GradientStop { position: 1; color: Theme.brandViolet }
                            }
                            Icon { anchors.centerIn: parent; text: "auto_awesome"; size: 24; fill: 1; color: "white" }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Txt { text: "Asistente Quantum"; font.pixelSize: Theme.textLarge + 1; font.weight: Font.Bold }
                            Txt {
                                Layout.fillWidth: true
                                text: Ai.status === "ready" ? "IA local · " + Ai.model + " · sin internet" : "IA que funciona en tu PC"
                                color: Theme.fgMuted; font.pixelSize: Theme.textSmall
                            }
                        }
                        IconButton { visible: Ai.messages.length > 0; icon: "edit_square"; onClicked: Ai.newChat() }
                        IconButton { icon: "close"; onClicked: Shell.aiOpen = false }
                    }

                    // ---------------------------------------------- conversación
                    ListView {
                        id: chat
                        visible: Ai.status === "ready"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 10
                        model: Ai.messages
                        onCountChanged: positionViewAtEnd()
                        onContentHeightChanged: if (Ai.busy) positionViewAtEnd()

                        delegate: Item {
                            id: msg
                            required property var modelData
                            required property int index
                            readonly property bool mine: modelData.role === "user"
                            width: chat.width
                            height: bubble.height
                            Rectangle {
                                id: bubble
                                anchors.right: msg.mine ? parent.right : undefined
                                width: Math.min(chat.width * (msg.mine ? 0.82 : 0.94), body.implicitWidth + 28)
                                height: body.implicitHeight + 22
                                radius: 18
                                color: msg.mine ? Theme.primaryContainer : Theme.surfaceHigh
                                Text {
                                    id: body
                                    x: 14; y: 11
                                    width: Math.min(chat.width * (msg.mine ? 0.82 : 0.94) - 28, implicitWidth)
                                    text: msg.modelData.content || (Ai.busy ? "…" : "")
                                    textFormat: msg.mine ? Text.PlainText : Text.MarkdownText
                                    wrapMode: Text.Wrap
                                    color: msg.mine ? Theme.primaryContainerFg : Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.textNormal
                                    onLinkActivated: link => Qt.openUrlExternally(link)
                                }
                            }
                        }

                        // sugerencias al empezar
                        Column {
                            visible: Ai.messages.length === 0
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: 10
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; text: "forum"; size: 44; color: Theme.primary }
                            Txt {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "¿En qué te ayudo?"
                                font.pixelSize: Theme.textTitle; font.weight: Font.Bold
                            }
                            Txt {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: "Pregúntame lo que quieras sobre Quantum, Linux o tu PC. Todo se queda en tu computador."
                                color: Theme.fgMuted
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                            }
                            Item { width: 1; height: 6 }
                            Repeater {
                                model: ["¿Cómo instalo un juego de Steam?", "¿Cómo cambio el estilo del escritorio?",
                                        "¿Qué es Proton y para qué sirve?", "Mi PC va lento, ¿qué puedo hacer?"]
                                Rectangle {
                                    required property string modelData
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(parent.width, sg.implicitWidth + 30); height: 42; radius: 21
                                    color: sgArea.containsMouse ? Theme.surfaceHighest : Theme.surfaceHigh
                                    Txt { id: sg; anchors.centerIn: parent; text: parent.modelData; font.weight: Font.DemiBold }
                                    MouseArea { id: sgArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Ai.send(parent.modelData) }
                                }
                            }
                        }
                    }

                    // -------------------------------------------- sin IA todavía
                    ColumnLayout {
                        visible: Ai.status === "missing" || Ai.status === "nomodel"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12
                        Item { Layout.fillHeight: true }
                        Icon { Layout.alignment: Qt.AlignHCenter; text: "download_for_offline"; size: 52; color: Theme.primary }
                        Txt {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Instala tu asistente"
                            font.pixelSize: Theme.textTitle; font.weight: Font.Bold
                        }
                        Txt {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: "La IA funciona en tu PC: no necesita cuentas ni envía tus datos a nadie. Elige un tamaño según tu equipo."
                            color: Theme.fgMuted; wrapMode: Text.WordWrap; elide: Text.ElideNone
                        }
                        Repeater {
                            model: win.tiers
                            Rectangle {
                                id: tc
                                required property var modelData
                                readonly property bool on: win.tier === modelData.m
                                Layout.fillWidth: true
                                implicitHeight: 62; radius: Theme.radius
                                color: on ? Theme.alpha(Theme.primary, 0.14) : Theme.surfaceHigh
                                border.width: on ? 2 : 0; border.color: Theme.primary
                                ColumnLayout {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 16
                                    spacing: 0
                                    Txt { text: tc.modelData.t + (tc.modelData.m === "gemma3:4b" ? "  (recomendado)" : ""); font.weight: Font.Bold }
                                    Txt { text: tc.modelData.h; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.tier = tc.modelData.m }
                            }
                        }
                        PillButton {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Instalar asistente"
                            icon: "download"
                            primary: true
                            onClicked: {
                                // instala Ollama (si falta), lo activa y descarga el modelo, en una terminal visible
                                Quickshell.execDetached(["kitty", "--class", "quantum-update", "--title", "Instalando el asistente", "bash", "-c",
                                    "echo -e '\\e[1;38;2;143;123;255mAsistente Quantum\\e[0m\\n'; " +
                                    "command -v ollama >/dev/null || sudo pacman -S --needed --noconfirm ollama; " +
                                    "sudo systemctl enable --now ollama && sleep 2 && ollama pull " + win.tier +
                                    " && echo -e '\\n\\e[1;32m¡Listo! Ya puedes cerrar esta ventana y usar el asistente (Super + H).\\e[0m'; " +
                                    "read -rp 'Presiona Enter para cerrar…'"]);
                                Settings.ai.model = win.tier;
                            }
                        }
                        PillButton {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Ya lo instalé, revisar otra vez"
                            onClicked: Ai.check()
                        }
                        Item { Layout.fillHeight: true }
                    }

                    // revisando
                    Item {
                        visible: Ai.status === "checking"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Txt { anchors.centerIn: parent; text: "Conectando con la IA…"; color: Theme.fgMuted }
                    }

                    // ---------------------------------------------- escribir
                    Rectangle {
                        visible: Ai.status === "ready"
                        Layout.fillWidth: true
                        implicitHeight: Math.min(140, Math.max(54, input.contentHeight + 30))
                        radius: 27
                        color: Theme.surfaceHigh
                        border.width: input.activeFocus ? 2 : 1
                        border.color: input.activeFocus ? Theme.primary : Theme.alpha(Theme.fg, 0.08)
                        TextEdit {
                            id: input
                            anchors.left: parent.left; anchors.right: sendBtn.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 20; anchors.rightMargin: 10
                            wrapMode: TextEdit.Wrap
                            font.family: Theme.font; font.pixelSize: Theme.textNormal
                            color: Theme.fg
                            selectionColor: Theme.primary
                            focus: true
                            Keys.onReturnPressed: e => {
                                if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return; }
                                Ai.send(text); text = "";
                            }
                            Keys.onEscapePressed: Shell.aiOpen = false
                            Txt { visible: !input.text; text: "Escribe tu pregunta…"; color: Theme.fgMuted }
                        }
                        Rectangle {
                            id: sendBtn
                            anchors.right: parent.right; anchors.rightMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40; height: 40; radius: 20
                            color: Ai.busy || input.text ? Theme.primary : Theme.surfaceHighest
                            Icon { anchors.centerIn: parent; text: Ai.busy ? "stop" : "arrow_upward"; fill: 1; color: Ai.busy || input.text ? Theme.primaryFg : Theme.fgMuted }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { if (Ai.busy) Ai.stop(); else { Ai.send(input.text); input.text = ""; } }
                            }
                        }
                    }
                    Txt {
                        visible: Ai.status === "ready"
                        Layout.alignment: Qt.AlignHCenter
                        text: "La IA puede equivocarse. Revisa lo importante."
                        color: Theme.fgMuted; font.pixelSize: Theme.textSmall - 1
                    }
                }
            }
        }
    }
}
