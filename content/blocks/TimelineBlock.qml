// TimelineBlock.qml
//
// A block drawn on its track. Drag horizontally to change the start time,
// drag the right edge to change the duration, drag up to the trash to delete.
//
// Blocks on different tracks may sit at the same time -- that is exactly how
// simultaneous movement is expressed, so nothing here pushes them apart.

import QtQuick
import DragonArm
import "../common"

Item {
    id: blockItem

    property int blockId: -1
    property real pixelsPerSecond: 72

    // An axis block sits in its own track, so the defaults fit: one lane, as
    // tall as the parent. A tool move is drawn in an overlay across all the
    // lanes and is told which ones it covers.
    property real laneHeight: parent ? parent.height : 48
    property int firstLane: 0
    property int laneCount: 1

    readonly property var data_: MovementPlan.revision, MovementPlan.block(blockId)
    readonly property bool isMove: !!data_ && data_.role === "move"
    readonly property var joint: data_ ? RobotLibrary.joint(data_.jointId) : null
    readonly property color accent: isMove ? RobotLibrary.moveAccent
                                           : (joint ? joint.accent : Theme.accent)
    // Tool moves only: how the planner resolved it, and the lanes it covers.
    readonly property var move: MovementPlan.revision, MovementPlan.moveInfo(blockId)
    readonly property var moveAxes: MovementPlan.revision,
                                    (isMove ? MovementPlan.blockAxes(blockId) : [])
    readonly property bool selected: AppState.selectedBlockId === blockId
    readonly property bool invalid: data_ ? data_.invalid : false
    readonly property real duration:
        MovementPlan.revision, MovementPlan.effectiveDuration(blockId)
    readonly property bool beingDragged: AppState.dragKind === AppState.dragBlock
                                         && AppState.dragBlockId === blockId

    readonly property string caption: {
        if (!data_)
            return ""
        if (isMove)
            return RobotLibrary.moveLabel(data_.direction)
        if (data_.role === "gripper") {
            var cmd = RobotLibrary.gripperCommand(data_.jointId, data_.commandId)
            return cmd ? cmd.name : data_.commandId
        }
        return data_.targetAngle.toFixed(0) + "°"
    }

    // Natural-speed moves are genuinely short (an MG996R sweeps 60 deg in about
    // 0.17 s), so the floor keeps them grabbable rather than faithful to scale.
    width: Math.max(26, duration * pixelsPerSecond)
    height: laneCount * laneHeight - 10
    y: firstLane * laneHeight + 5
    z: selected ? 10 : (beingDragged ? 9 : 1)

    // The plan owns x, except while the user is dragging the block.
    Binding {
        target: blockItem
        property: "x"
        value: blockItem.data_ ? blockItem.data_.startTime * blockItem.pixelsPerSecond : 0
        when: !moveArea.drag.active
        restoreMode: Binding.RestoreNone
    }

    Rectangle {
        id: body

        anchors.fill: parent
        radius: Theme.radiusSmall
        color: Theme.blend(Theme.surface, blockItem.accent,
                           blockItem.selected ? 0.42 : (moveArea.containsMouse ? 0.3 : 0.22))
        border.width: blockItem.selected || blockItem.invalid ? 2 : 1
        border.color: blockItem.invalid ? Theme.danger
                                        : (blockItem.selected ? Theme.textPrimary
                                                              : blockItem.accent)
        opacity: blockItem.beingDragged ? 0.7 : 1

        Behavior on color {
            ColorAnimation { duration: 80 }
        }

        // Solid start edge: the moment the movement begins.
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: 3
            radius: Theme.radiusSmall
            color: blockItem.invalid ? Theme.danger : blockItem.accent
        }

        Text {
            id: caption
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: blockItem.isMove ? -8 : 0
            visible: blockItem.width > 42
            text: blockItem.caption
            color: Theme.textPrimary
            font.family: blockItem.isMove ? Theme.fontFamily : Theme.monoFamily
            font.pixelSize: Theme.fontSmall
            font.bold: true
        }

        // Tool move: the distance sits under the direction.
        Text {
            anchors.left: caption.left
            anchors.top: caption.bottom
            anchors.topMargin: 1
            visible: blockItem.isMove && blockItem.width > 42
            text: blockItem.data_ ? blockItem.data_.distance.toFixed(0) + " mm" : ""
            color: blockItem.invalid ? Theme.danger : Theme.textSecondary
            font.family: Theme.monoFamily
            font.pixelSize: Theme.fontTiny
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            visible: !blockItem.isMove && blockItem.width > caption.implicitWidth + 86
            text: blockItem.duration.toFixed(2) + "s"
            color: Theme.textMuted
            font.family: Theme.monoFamily
            font.pixelSize: Theme.fontTiny
        }

        // Tool move: one row per lane it covers, showing the angle that axis
        // ends on -- the block is that many ordinary movements at once.
        Repeater {
            model: blockItem.isMove ? blockItem.moveAxes : []

            delegate: Item {
                id: laneRow
                required property var modelData
                required property int index

                readonly property var laneJoint: RobotLibrary.joint(modelData)
                readonly property real target:
                    blockItem.move && blockItem.move.toAngles[modelData] !== undefined
                    ? blockItem.move.toAngles[modelData] : NaN

                x: 0
                y: index * blockItem.laneHeight - 5
                width: body.width
                height: blockItem.laneHeight

                // Lane boundary, so the covered lanes stay readable.
                Rectangle {
                    visible: laneRow.index > 0
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 5
                    anchors.rightMargin: 1
                    height: 1
                    color: Theme.fade(blockItem.accent, 0.28)
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: blockItem.width > caption.implicitWidth + 84
                    spacing: 5

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: Theme.radiusSmall
                        color: laneRow.laneJoint ? laneRow.laneJoint.accent : blockItem.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: isNaN(laneRow.target) ? "–" : laneRow.target.toFixed(1) + "°"
                        color: Theme.textSecondary
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontTiny
                    }
                }
            }
        }
    }

    // ---- Move ----------------------------------------------------------
    MouseArea {
        id: moveArea

        anchors.fill: parent
        anchors.rightMargin: 8        // leave the resize grip free
        hoverEnabled: true
        preventStealing: true         // do not let the Flickable steal the drag
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        drag.target: blockItem
        drag.axis: Drag.XAxis
        drag.minimumX: 0
        drag.threshold: 3

        onPressed: AppState.selectBlock(blockItem.blockId)

        onPositionChanged: function (mouseEvent) {
            if (!drag.active)
                return
            var scene = mapToItem(null, mouseEvent.x, mouseEvent.y)
            if (!blockItem.beingDragged) {
                AppState.beginBlockDrag(blockItem.blockId,
                                        blockItem.data_ ? blockItem.data_.jointId : "",
                                        scene.x, scene.y)
            } else {
                AppState.updateDrag(scene.x, scene.y)
            }
        }

        onReleased: {
            var newStart = AppState.snap(blockItem.x / blockItem.pixelsPerSecond)

            // Delivers the drop first: the trash bin may delete this block.
            AppState.finishDrag()

            if (MovementPlan.indexOf(blockItem.blockId) !== -1)
                MovementPlan.setStartTime(blockItem.blockId, newStart)
        }

        onCanceled: AppState.cancelDrag()
    }

    // ---- Resize --------------------------------------------------------
    MouseArea {
        id: resizeArea

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 8
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeHorCursor

        property real pressSceneX: 0
        property real pressDuration: 1

        onPressed: function (mouseEvent) {
            AppState.selectBlock(blockItem.blockId)
            pressSceneX = mapToItem(null, mouseEvent.x, 0).x
            pressDuration = blockItem.duration
        }

        onPositionChanged: function (mouseEvent) {
            if (!pressed)
                return
            var dx = mapToItem(null, mouseEvent.x, 0).x - pressSceneX
            var seconds = pressDuration + dx / blockItem.pixelsPerSecond
            MovementPlan.setDuration(blockItem.blockId, AppState.snap(seconds))
        }

        // Grip marks
        Column {
            anchors.centerIn: parent
            spacing: 2
            opacity: resizeArea.containsMouse || blockItem.selected ? 1 : 0.35

            Repeater {
                model: 3

                delegate: Rectangle {
                    width: 8
                    height: 1
                    color: Theme.textPrimary
                }
            }
        }
    }
}
