import QtQuick

Rectangle {
    id: card
    default property alias content: contentItem.data
    property int horizontalPadding: 10

    color: Theme.paper
    border.color: Theme.border
    border.width: 1
    radius: 12
    implicitWidth: 100
    implicitHeight: 38

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.leftMargin: card.horizontalPadding
        anchors.rightMargin: card.horizontalPadding
    }
}
