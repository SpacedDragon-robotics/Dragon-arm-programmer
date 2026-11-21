// TimelineTrack.qml -- one servo's lane, plus its drop target.

import QtQuick
import DragonArm
import "../common"

Item {
    id: track

    property var joint: null
    property real pixelsPerSecond: 72
    property real span: 20
    property real majorStep: 1
    property int rowIndex: 0

    readonly property string jointId: joint ? joint.id : ""
    readonly property color accent: joint ? joint.accent : Theme.accent

    // Only the lanes the dragged chip would land on light up: one for an axis
    // chip, every axis it drives for a tool move.
    readonly property bool droppable: AppState.dragTargetAxes.indexOf(jointId) !== -1
    readonly property bool moveDrag: AppState.dragMoveDirection !== ""
    readonly property color dropAccent: moveDrag ? RobotLibrary.moveAccent : accent

    height: 48

    Rectangle {
        anchors.fill: parent
        color: rowIndex % 2 === 0 ? Theme.surface : Theme.surfaceAlt

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.border
        }
    }

    // Grid lines aligned with the ruler.
    Canvas {
        id: grid
        anchors.fill: parent

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: track
            function onPixelsPerSecondChanged() { grid.requestPaint() }
            function onMajorStepChanged() { grid.requestPaint() }
            function onSpanChanged() { grid.requestPaint() }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.lineWidth = 1

            var minor = track.majorStep / 5
            ctx.strokeStyle = Theme.fade(Theme.white, 0.035)
            for (var t = minor; t <= track.span; t += minor) {
                var x = Math.round(t * track.pixelsPerSecond) + 0.5
                if (x > width)
                    break
                ctx.beginPath()
                ctx.moveTo(x, 0)
                ctx.lineTo(x, height)
                ctx.stroke()
            }

            ctx.strokeStyle = Theme.border
            for (t = 0; t <= track.span; t += track.majorStep) {
                x = Math.round(t * track.pixelsPerSecond) + 0.5
                if (x > width)
                    break
                ctx.beginPath()
                ctx.moveTo(x, 0)
                ctx.lineTo(x, height)
                ctx.stroke()
            }
        }
    }

    // Drop highlight while a matching palette chip hovers this lane.
    Rectangle {
        anchors.fill: parent
        visible: track.droppable
        color: dropArea.containsDrag ? Theme.blend(Theme.surface, track.dropAccent, 0.2)
                                     : Theme.blend(Theme.surface, track.dropAccent, 0.08)
        border.width: dropArea.containsDrag ? 1 : 0
        border.color: track.dropAccent
    }

    // Preview of where the new block will land.
    Rectangle {
        visible: track.droppable && dropArea.containsDrag
        x: AppState.snap(Math.max(0, dropArea.drag.x) / track.pixelsPerSecond)
           * track.pixelsPerSecond
        y: 5
        width: 3
        height: parent.height - 10
        radius: Theme.radiusSmall
        color: track.dropAccent
    }

    DropArea {
        id: dropArea
        anchors.fill: parent
        keys: ["dragonarm.palette"]

        onDropped: function (drop) {
            if (!track.droppable)
                return
            var seconds = AppState.snap(Math.max(0, drop.x) / track.pixelsPerSecond)
            // A tool move dropped on any of its lanes covers all of them.
            var id = track.moveDrag
                    ? MovementPlan.addMoveBlock(AppState.dragMoveDirection, seconds)
                    : MovementPlan.addBlock(track.jointId, seconds)
            AppState.selectBlock(id)
            drop.accept()
        }
    }

    // ---- Blocks --------------------------------------------------------
    Repeater {
        model: {
            MovementPlan.revision
            var ids = []
            for (var i = 0; i < MovementPlan.blocks.count; ++i) {
                var b = MovementPlan.blocks.get(i)
                if (b.jointId === track.jointId)
                    ids.push(b.blockId)
            }
            return ids
        }

        delegate: TimelineBlock {
            required property var modelData

            blockId: modelData
            pixelsPerSecond: track.pixelsPerSecond
        }
    }
}
