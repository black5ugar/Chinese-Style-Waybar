import QtQuick

Rectangle {
    id: field

    property alias text: input.text
    property alias placeholderText: placeholder.text
    property bool password: false
    property bool revealPassword: false
    property bool readOnly: false
    signal accepted()

    function focus() {
        input.forceActiveFocus();
        input.selectAll();
    }

    width: parent ? parent.width : 320
    height: 42
    radius: 10
    color: Qt.rgba(1, 1, 1, 0.45)
    border.color: input.activeFocus ? Theme.cinnabar : Theme.border
    border.width: 1

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: field.password ? 42 : 12
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.ink
        selectionColor: Theme.cinnabar
        selectedTextColor: "white"
        font.family: Theme.fontFamily
        font.pixelSize: 13
        echoMode: field.password && !field.revealPassword ? TextInput.Password : TextInput.Normal
        passwordCharacter: "●"
        readOnly: field.readOnly
        Keys.onReturnPressed: field.accepted()
    }

    BarText {
        id: placeholder
        visible: input.text.length === 0 && !input.activeFocus
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.muted
        font.weight: Font.Normal
    }

    BarText {
        visible: field.password
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: field.revealPassword ? "󰈈" : "󰈉"
        color: Theme.muted
        font.pixelSize: 15

        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            cursorShape: Qt.PointingHandCursor
            onClicked: field.revealPassword = !field.revealPassword
        }
    }
}
