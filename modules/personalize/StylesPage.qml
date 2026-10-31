import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Estilos de un clic: los de Quantum (styles/*.json del shell) y los tuyos
// (~/.config/quantum/styles/*.json). Un estilo es un JSON con nombre, descripción
// y los ajustes que cambia; se puede compartir como archivo.
ColumnLayout {
    id: page

    spacing: 16
    property var styles: []
    readonly property string sysDir: Quickshell.shellDir + "/styles"
    // Los paquetes también pueden instalar estilos compartidos en /usr/share
    readonly property var sysDirs: [sysDir, "/usr/share/quantum/styles"]
    readonly property string userDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quantum/styles"
    property bool naming: false
    property string notice: ""

    function reload(): void { lister.running = true; }
    Component.onCompleted: reload()

    function say(text: string): void { notice = text; noticeTimer.restart(); }
    Timer { id: noticeTimer; interval: 3500; onTriggered: page.notice = "" }

    // Lee todos los estilos: «\x1e<ruta>\x1f<contenido>» por archivo.
    Process {
        id: lister
        command: ["sh", "-c", "for d in \"$@\"; do for f in \"$d\"/*.json; do [ -f \"$f\" ] && printf '\\036%s\\037' \"$f\" && cat \"$f\"; done; done", "sh"].concat(page.sysDirs).concat([page.userDir])
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const out = [];
                for (const chunk of text.split("\x1e")) {
                    const i = chunk.indexOf("\x1f");
                    if (i < 0) continue;
                    const path = chunk.substring(0, i);
                    try {
                        const j = JSON.parse(chunk.substring(i + 1));
                        const user = path.indexOf(page.userDir) === 0;
                        // «1-quantum.json» → «quantum» (el número solo ordena)
                        const file = path.substring(path.lastIndexOf("/") + 1).replace(/\.json$/, "").replace(/^\d+-/, "");
                        const id = (user ? "user:" : "") + file;
                        if (seen[id])       // el del shell gana sobre el de /usr/share
                            continue;
                        seen[id] = true;
                        out.push({
                            id: id,
                            path: path,
                            user: user,
                            name: j.name || file,
                            description: j.description || "",
                            settings: j.settings || {}
                        });
                    } catch (e) {
                        console.warn("Personalizar: estilo inválido", path, e);
                    }
                }
                page.styles = out;
            }
        }
    }

    // Escribe un archivo (contenido, ruta) y vuelve a leer la lista.
    Process {
        id: writer
        property string okText: ""
        onExited: code => { page.say(code === 0 ? okText : "No se pudo guardar el archivo"); page.reload(); }
    }
    function writeFile(path: string, content: string, okText: string): void {
        writer.okText = okText;
        writer.command = ["sh", "-c", "mkdir -p \"$(dirname \"$2\")\" && printf '%s\\n' \"$1\" > \"$2\"", "sh", content, path];
        writer.running = true;
    }

    // Lo que se guarda/comparte: el aspecto actual, sin el fondo (es de tu PC).
    function currentStyle(name: string): string {
        const v = Settings.visualState();
        delete v.appearance.wallpaper;
        delete v.ui;
        return JSON.stringify({ name: name, description: "Creado por ti", settings: v }, null, 2);
    }

    function slug(name: string): string {
        return name.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "mi-estilo";
    }

    // La miniatura de un estilo, con tu fondo actual (salvo que el estilo traiga uno).
    function preview(st: var): var {
        const v = Object.assign({}, st.settings);
        v.appearance = Object.assign({ wallpaper: Settings.appearance.wallpaper }, st.settings.appearance ?? {});
        return v;
    }

    // ------------------------------------------------------------ forma del shell
    Group {
        title: "Quantum Shell"
        help: Settings.ui.shell === "serpantium"
            ? "Serpantium: barra de píldoras, paneles oscuros y tonos rosados. Inspirado en Serpantinum de ilyamiro."
            : "Caelestial: barra arriba, dock y paneles de vidrio. Inspirado en Caelestia Shell, pero más liviano."
        icon: "dashboard"
        Segmented {
            options: [{ v: "caelestial", t: "Caelestial", i: "blur_on" }, { v: "serpantium", t: "Serpantium", i: "terminal" }]
            value: Settings.ui.shell
            onPicked: v => Serp.choose(v, false)
        }
    }

    // ------------------------------------------------------------ estilos
    Group {
        title: "Elige un estilo"
        help: "Cambia todo el escritorio de una vez. Después puedes ajustar cada detalle en las otras secciones."
        icon: "auto_awesome"

        GridLayout {
            Layout.fillWidth: true
            columns: page.width > 760 ? 3 : 2
            columnSpacing: 14
            rowSpacing: 14
            Repeater {
                model: page.styles.filter(s => !s.user)
                ChoiceCard {
                    id: sc
                    required property var modelData
                    title: modelData.name
                    help: modelData.description
                    selected: Settings.ui.style === modelData.id
                    previewHeight: 118
                    onClicked: Settings.applyStyle(modelData.id, modelData.settings)
                    MiniDesktop { anchors.fill: parent; v: page.preview(sc.modelData) }
                }
            }
        }

        Txt {
            visible: Settings.ui.style === "custom"
            Layout.fillWidth: true
            text: "Ahora tienes un estilo personalizado. Guárdalo en «Tus estilos» para no perderlo."
            color: Theme.primary
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }
    }

    // ------------------------------------------------------- tus estilos
    Group {
        title: "Tus estilos"
        help: "Guarda cómo tienes tu escritorio, o importa uno que te compartieron (por ejemplo, en el Discord de Quantum)."
        icon: "bookmark"

        GridLayout {
            visible: page.styles.some(s => s.user)
            Layout.fillWidth: true
            columns: page.width > 760 ? 3 : 2
            columnSpacing: 14
            rowSpacing: 14
            Repeater {
                model: page.styles.filter(s => s.user)
                ChoiceCard {
                    id: uc
                    required property var modelData
                    title: modelData.name
                    help: modelData.description
                    selected: Settings.ui.style === modelData.id
                    previewHeight: 104
                    onClicked: Settings.applyStyle(modelData.id, modelData.settings)
                    MiniDesktop { anchors.fill: parent; v: page.preview(uc.modelData) }
                    IconButton {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        icon: "delete"
                        iconSize: 18
                        onClicked: {
                            remover.command = ["rm", "-f", uc.modelData.path];
                            remover.running = true;
                        }
                    }
                }
            }
        }
        Process { id: remover; onExited: { page.say("Estilo borrado"); page.reload(); } }

        // poner nombre al guardar
        RowLayout {
            visible: page.naming
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: 21
                color: Theme.surfaceHigh
                border.width: 2
                border.color: nameInput.activeFocus ? Theme.primary : "transparent"
                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font
                    font.pixelSize: Theme.textNormal
                    color: Theme.fg
                    selectionColor: Theme.primary
                    clip: true
                    maximumLength: 40
                    onAccepted: saveBtn.clicked()
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !nameInput.text
                        text: "Nombre de tu estilo, por ejemplo «Mi setup»"
                        color: Theme.fgMuted
                    }
                }
            }
            PillButton {
                id: saveBtn
                text: "Guardar"
                icon: "check"
                primary: true
                onClicked: {
                    const name = nameInput.text.trim() || "Mi estilo";
                    page.writeFile(page.userDir + "/" + page.slug(name) + ".json", page.currentStyle(name), "Estilo «" + name + "» guardado");
                    page.naming = false;
                    nameInput.text = "";
                }
            }
            PillButton { text: "Cancelar"; onClicked: page.naming = false }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 10
            PillButton {
                visible: !page.naming
                text: "Guardar mi estilo"
                icon: "bookmark_add"
                primary: true
                onClicked: { page.naming = true; nameInput.forceActiveFocus(); }
            }
            PillButton { text: "Importar"; icon: "file_open"; onClicked: openDialog.open() }
            PillButton { text: "Exportar"; icon: "ios_share"; onClicked: saveDialog.open() }
        }

        Txt {
            visible: page.notice !== ""
            text: page.notice
            color: Theme.primary
            font.weight: Font.DemiBold
        }
    }

    // Importar: se valida el JSON y se copia a tus estilos
    FileDialog {
        id: openDialog
        title: "Importar un estilo de Quantum"
        nameFilters: ["Estilos de Quantum (*.json)"]
        onAccepted: {
            reader.command = ["cat", decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))];
            reader.running = true;
        }
    }
    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    if (!j.settings || typeof j.settings !== "object")
                        throw "sin ajustes";
                    const name = String(j.name || "Estilo importado").substring(0, 40);
                    page.writeFile(page.userDir + "/" + page.slug(name) + ".json",
                                   JSON.stringify({ name: name, description: j.description || "Importado", settings: j.settings }, null, 2),
                                   "Estilo «" + name + "» importado");
                } catch (e) {
                    page.say("Ese archivo no es un estilo de Quantum");
                }
            }
        }
    }

    // Exportar: el aspecto actual a un archivo para compartir
    FileDialog {
        id: saveDialog
        title: "Exportar mi estilo"
        fileMode: FileDialog.SaveFile
        currentFile: "file://" + Quickshell.env("HOME") + "/mi-estilo-quantum.json"
        nameFilters: ["Estilos de Quantum (*.json)"]
        onAccepted: {
            let path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
            if (!path.endsWith(".json")) path += ".json";
            page.writeFile(path, page.currentStyle("Mi estilo"), "Exportado: " + path);
        }
    }
}
