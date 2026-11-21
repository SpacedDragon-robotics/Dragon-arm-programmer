// BlockInspector.qml
//
// Parameter editor for the selected block: absolute target angle, duration
// and start time. Every control writes straight into MovementPlan, which
// revalidates the whole plan on each change.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm
import "../common"

PanelCard {
    id: inspector

    readonly property int blockId: AppState.selectedBlockId
    readonly property var block: MovementPlan.revision, MovementPlan.block(blockId)
    readonly property var joint: block ? RobotLibrary.joint(block.jointId) : null
    readonly property bool isGripper: !!joint && joint.role === "gripper"
    // A tool move has no joint of its own: it drives several.
    readonly property bool isMove: !!block && block.role === "move"
    readonly property bool has: !!block && (!!joint || isMove)
    readonly property color tint: isMove ? RobotLibrary.moveAccent
                                         : (joint ? joint.accent : Theme.accent)
    // Tool moves: how the planner resolved it (target point, angles, reason).
    readonly property var move: MovementPlan.revision, MovementPlan.moveInfo(blockId)
    readonly property var moveAxes: MovementPlan.revision,
                                    (isMove ? MovementPlan.blockAxes(blockId) : [])

    readonly property real effectiveDuration:
        MovementPlan.revision, MovementPlan.effectiveDuration(blockId)
    readonly property real startAngle:
        MovementPlan.revision, MovementPlan.startAngleOf(blockId)

    readonly property var blockIssues: MovementPlan.revision, MovementPlan.issuesForBlock(blockId)
    readonly property var peak: MovementPlan.revision, MovementPlan.peakDemand(blockId)
    // The axis whose limits the ramp editor compares against: the block's
    // own, or for a tool move the one it works hardest.
    readonly property var limitJoint: isMove ? RobotLibrary.joint(peak.jointId) : joint

    title: "Block inspector"
    subtitle: !has ? "nothing selected"
                   : (isMove ? "Move tool" : (joint ? joint.name : "")) + " · #" + blockId
    accent: tint

    content: [
        // ---- Empty state ------------------------------------------------
        Item {
            anchors.fill: parent
            visible: !inspector.has

            Text {
                anchors.centerIn: parent
                width: parent.width - 20
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Select a block on the timeline or in the list to edit its target angle "
                      + "or tool move, duration and start time."
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.weight: Theme.weightBody
                font.pixelSize: Theme.fontSmall
            }
        },

        // ---- Editor -----------------------------------------------------
        Flickable {
            anchors.fill: parent
            visible: inspector.has
            clip: true
            contentWidth: width
            contentHeight: editor.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: editor
                width: parent.width
                spacing: Theme.spacing

                // -- Gripper command -----------------------------------
                Column {
                    width: parent.width
                    spacing: Theme.spacingSmall
                    visible: inspector.isGripper

                    SectionHeader {
                        width: parent.width
                        text: "Command"
                    }

                    Row {
                        spacing: Theme.spacingSmall

                        Repeater {
                            model: inspector.isGripper && inspector.joint.commands
                                   ? inspector.joint.commands : []

                            delegate: Rectangle {
                                id: cmdButton
                                required property var modelData

                                readonly property bool active:
                                    inspector.block && inspector.block.commandId === modelData.id

                                width: 104
                                height: 46
                                radius: Theme.radiusSmall
                                color: active ? Theme.blend(Theme.surfaceAlt,
                                                            inspector.joint.accent, 0.3)
                                              : (cmdMouse.containsMouse ? Theme.surfaceHover
                                                                        : Theme.surfaceAlt)
                                border.width: 1
                                border.color: active ? inspector.joint.accent : Theme.border

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: cmdButton.modelData.name
                                        color: cmdButton.active ? Theme.textPrimary
                                                                : Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontBody
                                        font.weight: (cmdButton.active) ? Theme.weightStrong : Theme.weightBody
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: cmdButton.modelData.angle + "° absolute"
                                        color: Theme.textMuted
                                        font.family: Theme.monoFamily
                                        font.pixelSize: Theme.fontTiny
                                    }
                                }

                                MouseArea {
                                    id: cmdMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: MovementPlan.setGripperCommand(
                                                   inspector.blockId, cmdButton.modelData.id)
                                }
                            }
                        }
                    }
                }

                // -- Tool move: direction and distance -----------------
                Column {
                    width: parent.width
                    spacing: Theme.spacingSmall
                    visible: inspector.isMove

                    SectionHeader {
                        width: parent.width
                        text: "Direction"
                        hint: "as the robot sees it · straight line"
                    }

                    // Opposites stack: up / left / forward over down / right / back.
                    Repeater {
                        model: [["up", "left", "forward"], ["down", "right", "back"]]

                        delegate: Row {
                            id: directionRow
                            required property var modelData
                            spacing: Theme.spacingSmall

                            Repeater {
                                model: directionRow.modelData

                                delegate: Rectangle {
                                    id: directionButton
                                    required property var modelData

                                    readonly property bool active:
                                        inspector.isMove
                                        && inspector.block.direction === modelData

                                    width: (editor.width - 2 * Theme.spacingSmall) / 3
                                    height: 32
                                    radius: Theme.radiusSmall
                                    color: active ? Theme.blend(Theme.surfaceAlt,
                                                                inspector.tint, 0.3)
                                                  : (directionMouse.containsMouse
                                                     ? Theme.surfaceHover : Theme.surfaceAlt)
                                    border.width: 1
                                    border.color: active ? inspector.tint : Theme.border

                                    Text {
                                        anchors.centerIn: parent
                                        text: RobotLibrary.moveLabel(directionButton.modelData)
                                        color: directionButton.active ? Theme.textPrimary
                                                                      : Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontBody
                                        font.weight: (directionButton.active) ? Theme.weightStrong : Theme.weightBody
                                    }

                                    MouseArea {
                                        id: directionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: MovementPlan.setMoveDirection(
                                                       inspector.blockId,
                                                       directionButton.modelData)
                                    }
                                }
                            }
                        }
                    }

                    SectionHeader {
                        width: parent.width
                        text: "Distance"
                        hint: "from wherever the tool is when the block starts"
                    }

                    ParameterSlider {
                        width: parent.width
                        label: "TRAVEL"
                        suffix: " mm"
                        accent: inspector.tint
                        from: 1
                        to: MovementPlan.maxMoveDistance
                        stepSize: 1
                        decimals: 0
                        value: inspector.isMove ? inspector.block.distance : 0
                        onMoved: function (v) {
                            MovementPlan.setMoveDistance(inspector.blockId, v)
                        }
                    }

                    // What the move works out to: where the tool goes, and the
                    // angle each axis ends on to get it there.
                    Rectangle {
                        width: parent.width
                        height: resultColumn.implicitHeight + 2 * Theme.spacingSmall
                        radius: Theme.radiusSmall
                        color: Theme.surfaceAlt
                        border.width: inspector.move && !inspector.move.ok ? 1 : 0
                        border.color: Theme.danger

                        Column {
                            id: resultColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.rightMargin: Theme.spacingSmall
                            spacing: 3

                            function point(p) {
                                return p ? p.x.toFixed(0) + ", " + p.y.toFixed(0) + ", "
                                           + p.z.toFixed(0) : "–"
                            }

                            Text {
                                width: parent.width
                                text: "tool  " + resultColumn.point(inspector.move
                                                                     ? inspector.move.from : null)
                                      + "  →  " + resultColumn.point(inspector.move
                                                                      ? inspector.move.to : null)
                                      + "  mm"
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fontSmall
                                font.bold: true
                            }

                            Text {
                                width: parent.width
                                text: "x forward · y left · z up, from the base on the table"
                                color: Theme.textMuted
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.weight: Theme.weightBody
                                font.pixelSize: Theme.fontTiny
                            }

                            Repeater {
                                model: inspector.move && inspector.move.ok
                                       ? inspector.moveAxes : []

                                delegate: Row {
                                    id: axisRow
                                    required property var modelData
                                    readonly property var axisJoint: RobotLibrary.joint(modelData)
                                    spacing: Theme.spacingSmall

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6
                                        height: 6
                                        radius: Theme.radiusSmall
                                        color: axisRow.axisJoint ? axisRow.axisJoint.accent
                                                                 : inspector.tint
                                    }

                                    Text {
                                        width: 52
                                        text: axisRow.axisJoint ? axisRow.axisJoint.name : ""
                                        color: Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.weight: Theme.weightBody
                                        font.pixelSize: Theme.fontTiny
                                    }

                                    Text {
                                        text: inspector.move.fromAngles[axisRow.modelData].toFixed(1)
                                              + "°  →  "
                                              + inspector.move.toAngles[axisRow.modelData].toFixed(1)
                                              + "°"
                                        color: Theme.textSecondary
                                        font.family: Theme.monoFamily
                                        font.pixelSize: Theme.fontTiny
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: !!inspector.move && !inspector.move.ok
                                text: inspector.move && !inspector.move.ok
                                      ? "No such move: " + inspector.move.reason + "." : ""
                                wrapMode: Text.WordWrap
                                color: Theme.danger
                                font.family: Theme.fontFamily
                                font.weight: Theme.weightBody
                                font.pixelSize: Theme.fontTiny
                            }
                        }
                    }
                }

                // -- Angle ---------------------------------------------
                SectionHeader {
                    width: parent.width
                    visible: !inspector.isMove
                    text: "Target angle"
                    hint: "absolute position, not a relative move"
                }

                // Travel summary, so it is obvious the angle is not relative.
                Rectangle {
                    width: parent.width
                    height: 34
                    radius: Theme.radiusSmall
                    color: Theme.surfaceAlt
                    visible: !inspector.isMove

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingSmall

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "from " + inspector.startAngle.toFixed(1) + "°"
                            color: Theme.textMuted
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.fontSmall
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "→"
                            color: inspector.tint
                            font.pixelSize: Theme.fontBody
                            font.bold: true
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "to " + (inspector.block ? inspector.block.targetAngle.toFixed(1)
                                                           : "0") + "°"
                            color: Theme.textPrimary
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.fontSmall
                            font.bold: true
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "(" + Math.abs((inspector.block ? inspector.block.targetAngle : 0)
                                                 - inspector.startAngle).toFixed(1) + "° travel)"
                            color: Theme.textMuted
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.fontTiny
                        }
                    }
                }

                ParameterSlider {
                    width: parent.width
                    label: "ANGLE"
                    suffix: "°"
                    visible: !inspector.isMove
                    enabled: !inspector.isGripper
                    opacity: enabled ? 1 : 0.5
                    accent: inspector.tint
                    from: inspector.joint ? inspector.joint.nominalMin : 0
                    to: inspector.joint ? inspector.joint.nominalMax : 180
                    stepSize: 1
                    decimals: 0
                    limitFrom: inspector.joint ? inspector.joint.mechMin : NaN
                    limitTo: inspector.joint ? inspector.joint.mechMax : NaN
                    value: inspector.block ? inspector.block.targetAngle : 0
                    onMoved: function (v) { MovementPlan.setTargetAngle(inspector.blockId, v) }
                }

                Text {
                    width: parent.width
                    visible: inspector.isGripper
                    text: "The gripper angle follows the selected command. Change the mapping in "
                          + "Robot Model → Servo channels."
                    wrapMode: Text.WordWrap
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.weight: Theme.weightBody
                    font.pixelSize: Theme.fontTiny
                }

                // -- Duration ------------------------------------------
                SectionHeader {
                    width: parent.width
                    text: "Duration"
                    hint: inspector.block && inspector.block.naturalDuration
                          ? "natural · " + inspector.effectiveDuration.toFixed(2) + " s"
                          : "explicit"
                }

                AppCheckBox {
                    text: inspector.isMove
                          ? "Fastest the slowest axis allows (within speed and accel limits)"
                          : (RobotLibrary.isStepper
                             ? "Fastest this axis can travel (within its speed and accel limits)"
                             : "Natural speed (plain servo.write, full servo speed)")
                    accent: inspector.tint
                    checked: inspector.block ? inspector.block.naturalDuration : true
                    onToggled: MovementPlan.setNaturalDuration(inspector.blockId, checked)
                }

                ParameterSlider {
                    width: parent.width
                    label: "SECONDS"
                    suffix: " s"
                    enabled: inspector.block && !inspector.block.naturalDuration
                    opacity: enabled ? 1 : 0.5
                    accent: inspector.tint
                    from: RobotLibrary.currentModel.minDuration
                    to: 20
                    stepSize: 0.05
                    decimals: 2
                    value: inspector.effectiveDuration
                    onMoved: function (v) { MovementPlan.setDuration(inspector.blockId, v) }
                }

                // -- Acceleration ramp ---------------------------------
                // Only shown for arms whose motion is ramped (steppers).
                // Servos have their own built-in easing curve.
                RampEditor {
                    width: parent.width
                    visible: MovementPlan.supportsRamp
                    accent: inspector.tint
                    ramp: inspector.block ? inspector.block.rampFraction : 0.25
                    peakSpeed: inspector.peak.speed
                    peakAccel: inspector.peak.accel
                    maxSpeed: inspector.limitJoint && inspector.limitJoint.maxSpeedDegPerSec
                              ? inspector.limitJoint.maxSpeedDegPerSec : 0
                    maxAccel: inspector.limitJoint && inspector.limitJoint.maxAccelDegPerSec2
                              ? inspector.limitJoint.maxAccelDegPerSec2 : 0
                    onMoved: function (v) {
                        MovementPlan.setRampFraction(inspector.blockId, v)
                    }
                }

                // -- Start time ----------------------------------------
                SectionHeader {
                    width: parent.width
                    text: "Timeline position"
                    hint: "end at " + (inspector.block
                                       ? (inspector.block.startTime
                                          + inspector.effectiveDuration).toFixed(2) : "0") + " s"
                }

                ParameterSlider {
                    width: parent.width
                    label: "START"
                    suffix: " s"
                    accent: inspector.tint
                    from: 0
                    to: Math.max(20, MovementPlan.endTime + 10)
                    stepSize: 0.05
                    decimals: 2
                    value: inspector.block ? inspector.block.startTime : 0
                    onMoved: function (v) { MovementPlan.setStartTime(inspector.blockId, v) }
                }

                // -- Per-block problems --------------------------------
                Column {
                    width: parent.width
                    spacing: 6
                    visible: inspector.blockIssues.length > 0

                    SectionHeader {
                        width: parent.width
                        text: "Problems with this block"
                    }

                    Repeater {
                        model: inspector.blockIssues

                        delegate: IssueRow {
                            required property var modelData
                            width: editor.width
                            issue: modelData
                            compact: true
                        }
                    }
                }

                // -- Actions --------------------------------------------
                Row {
                    spacing: Theme.spacingSmall

                    AppButton {
                        text: "Duplicate"
                        variant: "secondary"
                        onClicked: AppState.selectBlock(
                                       MovementPlan.duplicateBlock(inspector.blockId))
                    }

                    AppButton {
                        text: "Delete"
                        variant: "secondary"
                        danger: true
                        onClicked: MovementPlan.removeBlock(inspector.blockId)
                    }
                }

                Item {
                    width: 1
                    height: 2
                }
            }
        }
    ]
}
