import QtQuick 2.0
import QtQuick.Effects
import SddmComponents 2.0

// Đăng nhập kiểu macOS: nền mờ, đồng hồ lớn ở trên, avatar + tên + ô mật khẩu ở giữa,
// nút nguồn ở dưới. Chỉ dùng QtQuick 2.0 để chạy được trên greeter Qt6 của SDDM.
Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#1c1c1e"

    LayoutMirroring.enabled: Qt.locale().textDirection == Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    // ---- nền ----
    Image {
        id: wallpaper
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }
    Rectangle {
        anchors.fill: parent
        color: "#40000000"
    }

    // ---- đồng hồ ----
    function refreshClock() {
        var d = new Date()
        timeText.text = Qt.formatTime(d, "hh:mm")
        dateText.text = Qt.formatDate(d, "dddd, d MMMM")
    }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.refreshClock()
    }
    Text {
        id: timeText
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.09
        color: "white"
        font.pixelSize: 112
        font.weight: Font.Light
        style: Text.Normal
    }
    Text {
        id: dateText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: timeText.bottom
        anchors.topMargin: -6
        color: "white"
        font.pixelSize: 24
        font.weight: Font.Medium
        opacity: 0.9
    }

    // ---- danh sách người dùng (vuốt / bấm mũi tên để đổi) ----
    ListView {
        id: userList
        width: 140
        height: 140
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.42
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        clip: true
        interactive: false
        model: userModel
        currentIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0

        delegate: Item {
            width: userList.width
            height: userList.height
            property string uname: model.name

            Item {
                id: avatarFrame
                anchors.centerIn: parent
                width: 120; height: 120

                // viền + nền tròn (hiện khi chưa có ảnh)
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.rgba(1, 1, 1, 0.25)
                    border.color: Qt.rgba(1, 1, 1, 0.55)
                    border.width: 2
                }

                // ảnh gốc ẩn, được cắt tròn bằng MultiEffect + mặt nạ tròn
                // (clip của Rectangle chỉ cắt theo hình chữ nhật, không theo radius)
                Image {
                    id: avatar
                    anchors.fill: parent
                    anchors.margins: 2
                    visible: false
                    source: model.icon
                    sourceSize: Qt.size(240, 240)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Rectangle {
                    id: avatarMask
                    anchors.fill: avatar
                    radius: width / 2
                    color: "black"
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: avatar
                    source: avatar
                    maskEnabled: true
                    maskSource: avatarMask
                    visible: avatar.status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: avatar.status !== Image.Ready
                    text: uname.length > 0 ? uname.charAt(0).toUpperCase() : "?"
                    color: "white"
                    font.pixelSize: 52
                    font.weight: Font.Medium
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.nextUser()
            }
        }
    }

    readonly property string currentName: userList.currentItem ? userList.currentItem.uname : ""

    function nextUser() {
        if (userList.count > 1)
            userList.currentIndex = (userList.currentIndex + 1) % userList.count
    }

    Text {
        id: nameText
        anchors.horizontalCenter: parent.horizontalCenter
        y: userList.y + userList.height + 10
        text: root.currentName
        color: "white"
        font.pixelSize: 22
        font.weight: Font.Medium
    }

    // ---- ô mật khẩu kiểu pill ----
    Item {
        id: pill
        width: 260; height: 40
        anchors.horizontalCenter: parent.horizontalCenter
        y: nameText.y + nameText.height + 14

        transform: Translate { id: shakeT }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.22)
            border.color: Qt.rgba(1, 1, 1, 0.35)
            border.width: 1
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            visible: password.text.length === 0
            text: "Nhập mật khẩu"
            color: Qt.rgba(1, 1, 1, 0.65)
            font.pixelSize: 15
        }

        TextInput {
            id: password
            anchors.left: parent.left
            anchors.right: goButton.left
            anchors.leftMargin: 18
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: 15
            echoMode: TextInput.Password
            passwordCharacter: "•"
            selectByMouse: true
            focus: true
            Keys.onReturnPressed: root.doLogin()
            Keys.onEnterPressed: root.doLogin()
        }

        // nút mũi tên tròn bên phải
        Rectangle {
            id: goButton
            width: 26; height: 26; radius: 13
            anchors.right: parent.right
            anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            opacity: password.text.length > 0 ? 1 : 0.35
            Text {
                anchors.centerIn: parent
                text: "→"
                color: "#1c1c1e"
                font.pixelSize: 16
                font.weight: Font.Bold
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.doLogin()
            }
        }
    }

    Text {
        id: errorText
        anchors.horizontalCenter: parent.horizontalCenter
        y: pill.y + pill.height + 10
        color: "#ff8a80"
        font.pixelSize: 13
        text: ""
    }

    // ---- nút nguồn ----
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48
        spacing: 16

        Repeater {
            model: [
                { label: "Khởi động lại", action: "reboot" },
                { label: "Tắt máy", action: "off" }
            ]
            Rectangle {
                width: 140; height: 34; radius: 17
                color: Qt.rgba(1, 1, 1, 0.16)
                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: "white"
                    font.pixelSize: 13
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: modelData.action === "reboot" ? sddm.reboot() : sddm.powerOff()
                }
            }
        }
    }

    // ---- logic đăng nhập ----
    function doLogin() {
        if (password.text.length === 0 || currentName.length === 0)
            return
        errorText.text = ""
        sddm.login(currentName, password.text, sessionModel.lastIndex)
    }

    SequentialAnimation {
        id: shake
        NumberAnimation { target: shakeT; property: "x"; to: -14; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 14; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 50 }
        NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 50 }
    }

    Connections {
        target: sddm
        onLoginFailed: {
            password.text = ""
            errorText.text = "Mật khẩu không đúng, vui lòng thử lại"
            shake.restart()
            password.forceActiveFocus()
        }
        onInformationMessage: errorText.text = message
    }

    Component.onCompleted: {
        refreshClock()
        password.forceActiveFocus()
    }
}
