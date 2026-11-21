// TrashBin.qml
//
// Drop target for deleting blocks. Drag a block out of the timeline and
// release it here; the bin only accepts existing blocks, never palette chips.

import QtQuick
import DragonArm
import "../common"

Rectangle {
    id: bin

    readonly property bool armed: AppState.dragKind === AppState.dragBlock
    readonly property bool hot: dropArea.containsDrag

    width: 116
    radius: Theme.radius
    color: hot ? Theme.dangerSoft : (armed ? Theme.surfaceAlt : "transparent")
    border.width: 1
    border.color: hot ? Theme.danger : (armed ? Theme.borderStrong : Theme.border)

    Behavior on color {
        ColorAnimation { duration: 100 }
    }

    Column {
        anchors.centerIn: parent
        spacing: 4

        NavIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "trash"
            width: 22
            height: 22
            color: bin.hot ? Theme.danger : (bin.armed ? Theme.textSecondary : Theme.textMuted)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: bin.hot ? "Release" : "Trash"
            color: bin.hot ? Theme.danger : (bin.armed ? Theme.textSecondary : Theme.textMuted)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontTiny
            font.weight: (bin.hot) ? Theme.weightStrong : Theme.weightBody
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "drag blocks here"
            color: Theme.textMuted
            opacity: bin.armed ? 0 : 0.8
            font.family: Theme.fontFamily
            font.weight: Theme.weightBody
            font.pixelSize: Theme.fontTiny
        }
    }

    DropArea {
        id: dropArea
        anchors.fill: parent
        keys: ["dragonarm.block"]

        onDropped: function (drop) {
            if (AppState.dragBlockId !== -1)
                MovementPlan.removeBlock(AppState.dragBlockId)
            drop.accept()
        }
    }
}
