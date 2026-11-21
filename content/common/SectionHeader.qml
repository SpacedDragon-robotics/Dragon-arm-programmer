// SectionHeader.qml -- small caps heading with a trailing rule.

import QtQuick
import DragonArm

Item {
    id: header

    property string text: ""
    property string hint: ""

    implicitHeight: 28
    height: implicitHeight

    Text {
        id: title
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        text: header.text.toUpperCase()
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTiny
        font.weight: Theme.weightStrong
        font.letterSpacing: 1.1
    }

    Text {
        id: hintText
        anchors.left: title.right
        anchors.leftMargin: Theme.spacingSmall
        anchors.baseline: title.baseline
        text: header.hint
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.weight: Theme.weightBody
        font.pixelSize: Theme.fontTiny
    }

    Rectangle {
        anchors.left: hintText.text.length > 0 ? hintText.right : title.right
        anchors.leftMargin: Theme.spacing
        anchors.right: parent.right
        anchors.verticalCenter: title.verticalCenter
        height: 1
        color: Theme.border
    }
}
