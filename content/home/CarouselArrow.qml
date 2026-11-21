// CarouselArrow.qml -- round previous/next control for the carousel.

import QtQuick
import DragonArm
import "../common"

Rectangle {
    id: arrow

    property string direction: "chevronLeft"

    signal activated()

    width: 36
    height: 36
    radius: Theme.radiusSmall
    color: arrowMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceAlt
    border.width: 1
    border.color: arrowMouse.containsMouse ? Theme.accent : Theme.border

    Behavior on color {
        ColorAnimation { duration: 100 }
    }

    NavIcon {
        anchors.centerIn: parent
        name: arrow.direction
        width: 18
        height: 18
        color: arrowMouse.containsMouse ? Theme.accentBright : Theme.textSecondary
    }

    MouseArea {
        id: arrowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: arrow.activated()
    }
}
