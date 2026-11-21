// BlockCard.qml
//
// Read-out of one block in the workspace list: what it commands, the absolute
// target angle, which way the servo turns, and its timing.
//
// Everything is derived from MovementPlan so the card can never drift out of
// sync with the timeline; `MovementPlan.revision` is what makes the derived
// values re-evaluate.

import QtQuick
import DragonArm
import "../common"

Rectangle {
    id: card

    property int blockId: -1

    readonly property var data_: MovementPlan.revision, MovementPlan.block(blockId)
    readonly property bool isMove: !!data_ && data_.role === "move"
    readonly property var joint: data_ ? RobotLibrary.joint(data_.jointId) : null
    readonly property color accent: isMove ? RobotLibrary.moveAccent
                                           : (joint ? joint.accent : Theme.accent)
    readonly property var move: MovementPlan.revision, MovementPlan.moveInfo(blockId)
    readonly property bool selected: AppState.selectedBlockId === blockId
    readonly property bool invalid: data_ ? data_.invalid : false

    readonly property real effectiveDuration:
        MovementPlan.revision, MovementPlan.effectiveDuration(blockId)
    readonly property real startAngle:
        MovementPlan.revision, MovementPlan.startAngleOf(blockId)
    readonly property string direction:
        MovementPlan.revision, MovementPlan.directionOf(blockId)

    readonly property string commandText: {
        if (!data_)
            return ""
        if (isMove) {
            // Which axes do the work, e.g. "Axis-2 · Axis-3 · Axis-4".
            var names = []
            var axes = MovementPlan.blockAxes(blockId)
            for (var i = 0; i < axes.length; ++i)
                names.push(RobotLibrary.jointName(axes[i]).replace("Axis-", "A"))
            return names.join(" · ")
        }
        if (data_.role === "gripper") {
            var cmd = RobotLibrary.gripperCommand(data_.jointId, data_.commandId)
            return cmd ? cmd.name : data_.commandId
        }
        return "Move to"
    }

    height: 64
    radius: Theme.radiusSmall
    color: selected ? Theme.blend(Theme.surfaceAlt, accent, 0.16)
                    : (cardMouse.containsMouse ? Theme.surfaceAlt : Theme.surface)
    border.width: 1
    border.color: invalid ? Theme.danger : (selected ? accent : Theme.border)

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
        color: card.invalid ? Theme.danger : card.accent
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 112
            spacing: 2

            Text {
                text: card.isMove ? "Move tool" : (card.joint ? card.joint.name : "")
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                font.weight: Theme.weightStrong
            }

            Text {
                text: card.commandText
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.weight: Theme.weightBody
                font.pixelSize: Theme.fontTiny
            }
        }

        // Tool move: direction and distance, then where the tool ends up.
        Row {
            visible: card.isMove
            anchors.left: parent.left
            anchors.leftMargin: 118
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingSmall

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.data_ ? RobotLibrary.moveLabel(card.data_.direction) : ""
                color: card.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                font.weight: Theme.weightStrong
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.data_ ? card.data_.distance.toFixed(0) + " mm" : ""
                color: card.invalid ? Theme.danger : Theme.textPrimary
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontTitle
                font.bold: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !!card.move && card.move.ok
                text: card.move
                      ? "→ " + card.move.to.x.toFixed(0) + ", " + card.move.to.y.toFixed(0)
                        + ", " + card.move.to.z.toFixed(0)
                      : ""
                color: Theme.textMuted
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontTiny
            }
        }

        // Travel: commanded start angle -> absolute target angle.
        Row {
            visible: !card.isMove
            anchors.left: parent.left
            anchors.leftMargin: 118
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingSmall

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.startAngle.toFixed(0) + "°"
                color: Theme.textMuted
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontSmall
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Arrow points the way the servo turns, never back along the row.
                text: card.direction === "up" ? "↑"
                                              : (card.direction === "down" ? "↓" : "•")
                color: card.direction === "hold" ? Theme.textMuted : card.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                font.weight: Theme.weightStrong
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.data_ ? card.data_.targetAngle.toFixed(0) + "°" : ""
                color: card.invalid ? Theme.danger : Theme.textPrimary
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontTitle
                font.bold: true
            }
        }

        Column {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                anchors.right: parent.right
                text: card.data_
                      ? "t " + card.data_.startTime.toFixed(2) + " – "
                        + (card.data_.startTime + card.effectiveDuration).toFixed(2) + " s"
                      : ""
                color: Theme.textSecondary
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontSmall
            }

            Text {
                anchors.right: parent.right
                text: card.effectiveDuration.toFixed(2) + " s"
                      + (card.data_ && card.data_.naturalDuration ? "  natural" : "")
                color: Theme.textMuted
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontTiny
            }
        }
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: AppState.selectBlock(card.blockId)
        onDoubleClicked: MovementPlan.duplicateBlock(card.blockId)
    }
}
