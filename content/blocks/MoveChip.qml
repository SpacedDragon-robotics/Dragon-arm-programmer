// MoveChip.qml
//
// One tool-move command in the palette ("↑ Up", "→ Right", ...). Drag it onto
// the timeline to create a move there, or click it to append one after
// everything already planned on the axes it drives.

import QtQuick
import DragonArm
import "../common"

Rectangle {
    id: chip

    // { id, name, glyph } from RobotLibrary.moveDirections.
    property var direction: null
    readonly property string directionId: direction ? direction.id : ""
    readonly property color accent: RobotLibrary.moveAccent

    readonly property bool dragging: AppState.dragKind === AppState.dragPalette
                                     && AppState.dragMoveDirection === chip.directionId

    signal quickAdd()

    width: 92
    height: 27
    radius: Theme.radiusSmall
    color: mouse.containsMouse || dragging ? Theme.surfaceHover : Theme.surfaceAlt
    border.width: 1
    border.color: mouse.containsMouse || dragging ? accent : Theme.border

    Behavior on color {
        ColorAnimation { duration: 90 }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 3
        radius: Theme.radiusSmall
        color: chip.accent
    }

    Text {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: 11
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        horizontalAlignment: Text.AlignHCenter
        text: chip.direction ? chip.direction.glyph : ""
        color: chip.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
        font.weight: Theme.weightStrong
    }

    Text {
        anchors.left: glyph.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: chip.direction ? chip.direction.name : ""
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSmall
        font.weight: Theme.weightStrong
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: chip.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property point pressPoint
        property bool moved: false

        onPressed: function (mouseEvent) {
            pressPoint = Qt.point(mouseEvent.x, mouseEvent.y)
            moved = false
        }

        onPositionChanged: function (mouseEvent) {
            if (!pressed)
                return
            var scene = mapToItem(null, mouseEvent.x, mouseEvent.y)
            if (!moved) {
                // Small threshold so a click is never mistaken for a drag.
                if (Math.abs(mouseEvent.x - pressPoint.x) < 5
                        && Math.abs(mouseEvent.y - pressPoint.y) < 5)
                    return
                moved = true
                AppState.beginMovePaletteDrag(chip.directionId, scene.x, scene.y)
            }
            AppState.updateDrag(scene.x, scene.y)
        }

        onReleased: {
            if (moved)
                AppState.finishDrag()
            else
                chip.quickAdd()
            moved = false
        }

        onCanceled: {
            AppState.cancelDrag()
            moved = false
        }
    }
}
