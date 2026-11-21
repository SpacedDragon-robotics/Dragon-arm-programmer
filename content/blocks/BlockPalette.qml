// BlockPalette.qml
//
// Command blocks available for the selected robot. The list comes straight
// from the robot model, so changing model changes the palette: one chip per
// axis, plus the six tool moves when the model describes its geometry.

import QtQuick
import DragonArm
import "../common"

PanelCard {
    id: palette

    title: "Block palette"
    subtitle: RobotLibrary.currentModelName + " · drag onto a track, or click to append"

    content: [
        Row {
            id: chipRow
            anchors.fill: parent
            spacing: Theme.spacingSmall

            Repeater {
                model: RobotLibrary.joints

                delegate: PaletteChip {
                    required property var modelData

                    joint: modelData
                    height: parent.height

                    onQuickAdd: {
                        // After everything already planned on that axis,
                        // tool moves included.
                        var id = MovementPlan.addBlock(
                                    modelData.id, MovementPlan.appendTime([modelData.id]))
                        AppState.selectBlock(id)
                    }
                }
            }

            // ---- Tool moves ---------------------------------------------
            Rectangle {
                visible: RobotLibrary.hasKinematics
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height - 8
                color: Theme.border
            }

            Column {
                visible: RobotLibrary.hasKinematics
                height: parent.height
                spacing: 4

                Repeater {
                    // Two rows of three: up / left / forward over
                    // down / right / back, so opposites stack.
                    model: [["up", "left", "forward"], ["down", "right", "back"]]

                    delegate: Row {
                        id: moveRow
                        required property var modelData
                        spacing: 4

                        Repeater {
                            model: moveRow.modelData

                            delegate: MoveChip {
                                required property var modelData

                                direction: RobotLibrary.moveDirection(modelData)
                                height: (chipRow.height - 4) / 2

                                onQuickAdd: {
                                    var id = MovementPlan.addMoveBlock(
                                                modelData,
                                                MovementPlan.appendTime(
                                                    RobotLibrary.moveAxes(modelData)))
                                    AppState.selectBlock(id)
                                }
                            }
                        }
                    }
                }
            }
        }
    ]
}
