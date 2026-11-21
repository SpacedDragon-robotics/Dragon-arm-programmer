// BlockWorkspace.qml
//
// Every block in the plan, in execution order. Selecting a card here is the
// same selection the timeline and the inspector use.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm
import "../common"

PanelCard {
    id: workspace

    title: "Movement blocks"
    subtitle: MovementPlan.blockCount + (MovementPlan.blockCount === 1 ? " block" : " blocks")
              + " · plan length " + MovementPlan.endTime.toFixed(2) + " s"

    // Execution order: by start time, then by axis so stacked blocks always
    // list in the same sequence.
    readonly property var orderedIds: {
        MovementPlan.revision
        var rows = []
        for (var i = 0; i < MovementPlan.blocks.count; ++i) {
            var b = MovementPlan.blocks.get(i)
            rows.push({
                id: b.blockId,
                start: b.startTime,
                axis: RobotLibrary.jointIndex(b.jointId)
            })
        }
        rows.sort(function (a, b) {
            if (Math.abs(a.start - b.start) > 1e-6)
                return a.start - b.start
            return a.axis - b.axis
        })
        var ids = []
        for (i = 0; i < rows.length; ++i)
            ids.push(rows[i].id)
        return ids
    }

    content: [
        ListView {
            id: list

            anchors.fill: parent
            clip: true
            spacing: 6
            model: workspace.orderedIds
            visible: MovementPlan.blockCount > 0

            ScrollBar.vertical: ScrollBar {
                id: listScrollBar
                policy: list.contentHeight > list.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }

            delegate: BlockCard {
                required property var modelData

                width: list.width - (listScrollBar.visible ? 12 : 0)
                blockId: modelData
            }
        },

        Item {
            anchors.fill: parent
            visible: MovementPlan.blockCount === 0

            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingSmall

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No blocks yet"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.weightStrong
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "Drag a block from the palette onto a timeline track,\n"
                          + "or click a palette block to append one."
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.weight: Theme.weightBody
                    font.pixelSize: Theme.fontSmall
                }

                Item {
                    width: 1
                    height: Theme.spacingSmall
                }

                AppButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Load example sequence"
                    variant: "secondary"
                    onClicked: MovementPlan.loadExample()
                }
            }
        }
    ]
}
