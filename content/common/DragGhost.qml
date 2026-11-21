// DragGhost.qml -- the chip that follows the cursor during a drag.

import QtQuick
import DragonArm

Rectangle {
    id: ghost

    readonly property bool isMove: AppState.dragMoveDirection !== ""
    readonly property string name: isMove ? RobotLibrary.moveLabel(AppState.dragMoveDirection)
                                          : RobotLibrary.jointName(AppState.dragJointId)
    readonly property color accent: isMove ? RobotLibrary.moveAccent
                                           : RobotLibrary.jointAccent(AppState.dragJointId)
    readonly property bool deleting: AppState.dragKind === AppState.dragBlock

    width: label.implicitWidth + 26
    height: 28
    radius: Theme.radiusSmall
    color: Theme.blend(Theme.surfaceHigh, accent, 0.28)
    border.width: 1
    border.color: accent
    opacity: 0.94

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: 14
        radius: Theme.radiusSmall
        color: ghost.accent
    }

    Text {
        id: label
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: 5
        text: ghost.deleting ? ghost.name + " block" : ghost.name
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSmall
        font.weight: Theme.weightStrong
    }
}
