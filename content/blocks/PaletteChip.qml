// PaletteChip.qml
//
// One command block in the palette. Drag it onto a timeline track to create a
// block there, or click it to append one after the end of that axis.

import QtQuick
import DragonArm
import "../common"

Rectangle {
    id: chip

    property var joint: null
    readonly property string jointId: joint ? joint.id : ""
    readonly property color accent: joint ? joint.accent : Theme.accent

    signal quickAdd()

    width: 148
    height: 58
    radius: Theme.radius
    color: mouse.containsMouse || dragging ? Theme.surfaceHover : Theme.surfaceAlt
    border.width: 1
    border.color: mouse.containsMouse || dragging ? accent : Theme.border

    property bool dragging: AppState.dragKind === AppState.dragPalette
                            && AppState.dragJointId === chip.jointId

    Behavior on color {
        ColorAnimation { duration: 90 }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 4
        radius: Theme.radiusSmall
        color: chip.accent
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingSmall
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            text: chip.joint ? chip.joint.name : ""
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBody
            font.weight: Theme.weightStrong
        }

        Text {
            width: parent.width
            text: chip.joint ? chip.joint.subtitle : ""
            color: Theme.textMuted
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.weight: Theme.weightBody
            font.pixelSize: Theme.fontTiny
        }

        Text {
            width: parent.width
            text: RobotLibrary.jointSummary(chip.jointId)
            color: Theme.fade(chip.accent, 0.85)
            elide: Text.ElideRight
            font.family: Theme.monoFamily
            font.pixelSize: Theme.fontTiny
        }
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
                AppState.beginPaletteDrag(chip.jointId, scene.x, scene.y)
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
