// BlocksModule.qml
//
// Visual programming workspace:
//   top    palette + trash bin
//   middle block list and the parameter inspector, with live validation
//   bottom the timeline

import QtQuick
import DragonArm
import "../common"

Item {
    id: blocksModule

    readonly property int sideWidth: Math.max(330, Math.round(width * 0.27))
    readonly property int timelineHeight: Math.max(250, Math.round(height * 0.38))

    focus: visible

    Keys.onPressed: function (event) {
        if (AppState.selectedBlockId === -1)
            return
        if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            MovementPlan.removeBlock(AppState.selectedBlockId)
            event.accepted = true
        } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            AppState.selectBlock(MovementPlan.duplicateBlock(AppState.selectedBlockId))
            event.accepted = true
        }
    }

    // ---- Palette + trash -----------------------------------------------
    Item {
        id: topRow

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing
        height: 106

        BlockPalette {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: trash.left
            anchors.rightMargin: Theme.spacing
        }

        TrashBin {
            id: trash
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }
    }

    // ---- Workspace + inspector -----------------------------------------
    Item {
        id: middleRow

        anchors.top: topRow.bottom
        anchors.topMargin: Theme.spacing
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: timeline.top
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        anchors.bottomMargin: Theme.spacing

        BlockWorkspace {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: sideColumn.left
            anchors.rightMargin: Theme.spacing
        }

        Item {
            id: sideColumn

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: blocksModule.sideWidth

            BlockInspector {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: validation.top
                anchors.bottomMargin: Theme.spacing
            }

            ValidationPanel {
                id: validation
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                // The inspector is the panel that earns the space: it holds the
                // angle, duration and ramp controls.
                height: Math.max(128, Math.round(parent.height * 0.28))
            }
        }
    }

    // ---- Timeline -------------------------------------------------------
    TimelinePanel {
        id: timeline

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing
        height: blocksModule.timelineHeight
    }
}
