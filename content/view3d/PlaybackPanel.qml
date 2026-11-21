// PlaybackPanel.qml
//
// Compact timeline for the 3D view: transport controls, one lane per axis
// with the plan's blocks on it, and a scrub slider underneath.
//
// The blocks can be edited here, as on the Blocks timeline:
//   click              select (the same selection Blocks uses)
//   drag               move it in time (snaps like the Blocks timeline)
//   drag right edge    change its duration
//   double-click       back to the fastest the axes allow
//   Delete / button    remove the selected block
// A tool move is ONE bar across every lane it drives. Every change goes
// through MovementPlan, so the 3D pose, the validator and the sketch follow.
//
// Lanes, playhead and slider share one horizontal scale (`trackX` /
// `trackWidth`), so the handle always sits exactly under the playhead. While
// a block is being moved or stretched that scale is frozen (`editSpan`), or
// the bars would slide under the cursor as the plan's length changes.

import QtQuick
import DragonArm
import "../common"

PanelCard {
    id: panel

    property real time: 0
    property real duration: 0
    property bool playing: false
    property bool looping: false
    property real speed: 1.0

    signal playToggled()
    signal restartRequested()
    signal seekRequested(real seconds)
    signal loopToggled()
    signal speedPicked(real speed)
    signal deleteRequested()

    readonly property int labelWidth: 70
    readonly property int laneHeight: 18
    readonly property int laneGap: 4
    readonly property int handleSize: 14
    readonly property int lanePitch: laneHeight + laneGap

    // Shown span: the plan, or a short empty ruler when there is none --
    // frozen, with room to grow, while a block is being edited.
    property bool editing: false
    property real editSpan: 0
    readonly property real span: editing ? Math.max(editSpan, duration) : Math.max(duration, 1)

    // Freeze the scale exactly as it is: nothing jumps on the press. It can
    // still grow (a block stretched past the end), never shrink mid-drag.
    function beginEdit() {
        editSpan = Math.max(duration, 1)
        editing = true
    }

    function endEdit() {
        editing = false
    }

    title: "Playback"
    subtitle: duration > 0
              ? "Space plays · drag a block to move it · drag its right edge for its duration · "
                + "double-click: fastest · Delete removes"
              : "No movements yet -- pose the arm above, or add blocks in the Blocks section"

    // ---- Blocks as bars -----------------------------------------------------

    // Joint accents are strings in the model; Theme.blend() needs colours.
    function colour(c) {
        return Qt.lighter(c, 1.0)
    }

    // Everything a bar needs for one block, or null if it has no lane here.
    function barInfo(blockId) {
        var b = MovementPlan.block(blockId)
        if (!b)
            return null
        var axes = MovementPlan.blockAxes(blockId)
        var lo = -1, hi = -1
        for (var i = 0; i < axes.length; ++i) {
            var lane = RobotLibrary.jointIndex(axes[i])
            if (lane < 0)
                continue
            lo = lo < 0 ? lane : Math.min(lo, lane)
            hi = Math.max(hi, lane)
        }
        if (lo < 0)
            return null

        var isMove = b.role === "move"
        var caption
        if (isMove) {
            caption = RobotLibrary.moveLabel(b.direction) + " " + b.distance.toFixed(0) + " mm"
        } else if (b.role === "gripper") {
            var cmd = RobotLibrary.gripperCommand(b.jointId, b.commandId)
            caption = cmd ? cmd.name : b.commandId
        } else {
            caption = b.targetAngle.toFixed(0) + "°"
        }
        return {
            name: isMove ? "Move tool" : RobotLibrary.jointName(b.jointId),
            start: b.startTime,
            end: MovementPlan.endTimeOf(blockId),
            first: lo,
            count: hi - lo + 1,
            accent: colour(isMove ? RobotLibrary.moveAccent : RobotLibrary.jointAccent(b.jointId)),
            caption: caption,
            invalid: b.invalid,
            natural: b.naturalDuration
        }
    }

    // Unclamped: a block may be moved past the current end of the plan.
    function xToStart(x) {
        return Math.max(0, (x - trackX) / trackWidth * span)
    }

    readonly property var selectedInfo:
        (MovementPlan.revision, AppState.selectedBlockId >= 0 ? barInfo(AppState.selectedBlockId) : null)

    implicitHeight: 38 + transport.height + Theme.spacingSmall + lanes.height
                    + Theme.spacingSmall + scrub.height + 18 + Theme.spacing

    function timeToX(t) {
        return trackX + (Math.max(0, Math.min(span, t)) / span) * trackWidth
    }

    function xToTime(x) {
        return Math.max(0, Math.min(duration, (x - trackX) / trackWidth * span))
    }

    readonly property real trackX: labelWidth + handleSize / 2
    readonly property real trackWidth: Math.max(1, contentItem.width - trackX - handleSize / 2)

    // Tick spacing: the smallest "nice" step that keeps labels ~70 px apart.
    readonly property real tickStep: {
        var steps = [0.5, 1, 2, 5, 10, 15, 30, 60, 120]
        for (var i = 0; i < steps.length; ++i) {
            if (steps[i] / span * trackWidth >= 70)
                return steps[i]
        }
        return steps[steps.length - 1]
    }

    function formatTime(t) {
        return t.toFixed(2) + " s"
    }

    content: [
        Item {
            id: body
            anchors.fill: parent

            // ---- Transport ----------------------------------------------------------
            Item {
                id: transport

                width: parent.width
                height: 34

                Row {
                    id: buttons
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingSmall

                    IconButton {
                        icon: "restart"
                        tooltipText: "Back to the start (Home)"
                        enabled: panel.duration > 0
                        onClicked: panel.restartRequested()
                    }

                    IconButton {
                        icon: panel.playing ? "pause" : "play"
                        primary: true
                        tooltipText: panel.playing ? "Pause (Space)" : "Play (Space)"
                        enabled: panel.duration > 0
                        onClicked: panel.playToggled()
                    }

                    IconButton {
                        icon: "loop"
                        checked: panel.looping
                        tooltipText: panel.looping ? "Looping" : "Play once"
                        onClicked: panel.loopToggled()
                    }
                }

                Text {
                    id: clock
                    anchors.left: buttons.right
                    anchors.leftMargin: Theme.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.formatTime(panel.time) + "  /  " + panel.formatTime(panel.duration)
                    color: Theme.textPrimary
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontBody
                }

                // The selected block, and the way to delete it.
                Row {
                    anchors.left: clock.right
                    anchors.leftMargin: Theme.spacingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingSmall
                    visible: !!panel.selectedInfo

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: Theme.radiusSmall
                        color: panel.selectedInfo ? panel.selectedInfo.accent : Theme.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.selectedInfo
                              ? panel.selectedInfo.name + "  " + panel.selectedInfo.caption + "  ·  "
                                + panel.selectedInfo.start.toFixed(2) + " – "
                                + panel.selectedInfo.end.toFixed(2) + " s"
                                + (panel.selectedInfo.natural ? "  ·  fastest" : "")
                              : ""
                        color: panel.selectedInfo && panel.selectedInfo.invalid ? Theme.danger
                                                                                : Theme.textSecondary
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontSmall
                    }

                    AppButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Delete"
                        variant: "ghost"
                        danger: true
                        implicitWidth: 62
                        implicitHeight: 24
                        onClicked: panel.deleteRequested()
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        rightPadding: 4
                        text: "Speed"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightBody
                        font.pixelSize: Theme.fontSmall
                    }

                    Repeater {
                        model: [0.25, 0.5, 1, 2]

                        Rectangle {
                            required property real modelData
                            readonly property bool selected: Math.abs(panel.speed - modelData) < 1e-6

                            width: 46
                            height: 24
                            radius: Theme.radiusSmall
                            color: selected ? Theme.accentSoft
                                            : (speedMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceAlt)
                            border.width: 1
                            border.color: selected ? Theme.accent : Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData + "×"
                                color: parent.selected ? Theme.accentBright : Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSmall
                                font.weight: (parent.selected) ? Theme.weightStrong : Theme.weightBody
                            }

                            MouseArea {
                                id: speedMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.speedPicked(parent.modelData)
                            }
                        }
                    }
                }
            }

            // ---- Lanes ----------------------------------------------------------------
            Item {
                id: lanes

                anchors.top: transport.bottom
                anchors.topMargin: Theme.spacingSmall
                width: parent.width
                height: RobotLibrary.joints.length * panel.lanePitch - panel.laneGap

                Repeater {
                    model: RobotLibrary.joints

                    Item {
                        id: lane
                        required property var modelData
                        required property int index

                        y: index * panel.lanePitch
                        width: lanes.width
                        height: panel.laneHeight

                        Text {
                            width: panel.labelWidth - Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            text: lane.modelData.name
                            elide: Text.ElideRight
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.weight: Theme.weightBody
                            font.pixelSize: Theme.fontTiny
                        }

                        Rectangle {
                            x: panel.trackX
                            width: panel.trackWidth
                            height: parent.height
                            radius: Theme.radiusSmall
                            color: Theme.surfaceAlt
                        }
                    }
                }
            }

            // Scrubbing works on the empty lanes as well as on the slider.
            // Declared before the bars, so a press on a bar goes to the bar.
            MouseArea {
                id: scrubMouse

                x: panel.labelWidth
                y: lanes.y - 4
                width: body.width - panel.labelWidth
                height: scrub.y + scrub.height + 4 - y
                enabled: panel.duration > 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                onPressed: function (mouse) {
                    AppState.clearSelection()
                    panel.seekRequested(panel.xToTime(mouse.x + x))
                }
                onPositionChanged: function (mouse) {
                    if (pressed)
                        panel.seekRequested(panel.xToTime(mouse.x + x))
                }
            }

            // ---- Blocks ------------------------------------------------------------
            Item {
                id: barLayer
                x: 0
                y: lanes.y
                width: lanes.width
                height: lanes.height

                Repeater {
                    // Block ids only: the array stays equal while a block is
                    // stretched, so the bar being dragged is never rebuilt.
                    model: {
                        MovementPlan.revision
                        var ids = []
                        for (var i = 0; i < MovementPlan.blocks.count; ++i)
                            ids.push(MovementPlan.blocks.get(i).blockId)
                        return ids
                    }

                    delegate: Item {
                        id: bar
                        required property int modelData

                        readonly property int blockId: modelData
                        readonly property var info: (MovementPlan.revision, panel.barInfo(blockId))
                        readonly property bool selected: AppState.selectedBlockId === blockId
                        readonly property bool active: !!info && panel.time >= info.start
                                                       && panel.time <= info.end
                        readonly property bool busy: moveArea.drag.active || resizeArea.pressed

                        visible: !!info
                        y: info ? info.first * panel.lanePitch : 0
                        height: info ? info.count * panel.lanePitch - panel.laneGap : 0
                        width: info ? Math.max(8, panel.timeToX(info.end) - panel.timeToX(info.start)) : 0
                        z: selected || busy ? 2 : 1

                        // The plan owns x, except while the bar is being dragged.
                        Binding {
                            target: bar
                            property: "x"
                            value: bar.info ? panel.timeToX(bar.info.start) : 0
                            when: !moveArea.drag.active
                            restoreMode: Binding.RestoreNone
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSmall
                            color: bar.info
                                   ? Theme.blend(Theme.surface, bar.info.accent,
                                                 bar.selected ? 0.62 : (bar.active || moveArea.containsMouse
                                                                        ? 0.48 : 0.32))
                                   : Theme.surface
                            border.width: bar.selected || (bar.info && bar.info.invalid) ? 2 : 1
                            border.color: bar.info && bar.info.invalid ? Theme.danger
                                          : (bar.selected ? Theme.textPrimary
                                                          : (bar.info ? bar.info.accent : Theme.border))
                            opacity: moveArea.drag.active ? 0.75 : 1

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                visible: bar.width > 34
                                text: bar.info ? bar.info.caption : ""
                                elide: Text.ElideRight
                                color: Theme.textPrimary
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fontTiny
                                font.bold: true
                            }
                        }

                        // Where it will start, while it is being moved.
                        Rectangle {
                            visible: moveArea.drag.active
                            x: 0
                            y: -height - 3
                            width: startLabel.implicitWidth + 10
                            height: startLabel.implicitHeight + 4
                            radius: Theme.radiusSmall
                            color: Theme.surfaceHigh
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                id: startLabel
                                anchors.centerIn: parent
                                text: AppState.snap(panel.xToStart(bar.x)).toFixed(2) + " s"
                                color: Theme.textPrimary
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fontTiny
                            }
                        }

                        // ---- Move -------------------------------------------
                        MouseArea {
                            id: moveArea
                            anchors.fill: parent
                            anchors.rightMargin: 7          // leave the edge to resizing
                            hoverEnabled: true
                            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            drag.target: bar
                            drag.axis: Drag.XAxis
                            drag.minimumX: panel.trackX
                            drag.threshold: 3
                            // Follow the point that was pressed exactly; the
                            // default ("smoothed") drops the distance covered
                            // before the threshold, and a fast flick loses a lot.
                            drag.smoothed: false

                            onPressed: {
                                AppState.selectBlock(bar.blockId)
                                panel.beginEdit()
                            }
                            onReleased: {
                                if (drag.active)
                                    MovementPlan.setStartTime(bar.blockId,
                                                              AppState.snap(panel.xToStart(bar.x)))
                                panel.endEdit()
                            }
                            onCanceled: panel.endEdit()
                            onDoubleClicked: MovementPlan.setNaturalDuration(bar.blockId, true)
                        }

                        // ---- Resize -----------------------------------------
                        MouseArea {
                            id: resizeArea
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 7
                            hoverEnabled: true
                            cursorShape: Qt.SizeHorCursor

                            property real pressX: 0
                            property real pressDuration: 0
                            // Seconds per pixel at the press: if the plan
                            // grows and the view rescales, the duration
                            // still follows the mouse one-to-one.
                            property real secondsPerPixel: 0

                            onPressed: function (m) {
                                AppState.selectBlock(bar.blockId)
                                panel.beginEdit()
                                pressX = mapToItem(null, m.x, 0).x
                                pressDuration = bar.info ? bar.info.end - bar.info.start : 0
                                secondsPerPixel = panel.span / panel.trackWidth
                            }
                            onPositionChanged: function (m) {
                                if (!pressed)
                                    return
                                var dx = mapToItem(null, m.x, 0).x - pressX
                                var seconds = pressDuration + dx * secondsPerPixel
                                MovementPlan.setDuration(bar.blockId, AppState.snap(seconds))
                            }
                            onReleased: panel.endEdit()
                            onCanceled: panel.endEdit()

                            // grip
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                opacity: resizeArea.containsMouse || bar.selected ? 1 : 0.4
                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        width: 5
                                        height: 1
                                        color: Theme.textPrimary
                                    }
                                }
                            }
                        }
                    }
                }

                // Playhead across all lanes, above the bars.
                Rectangle {
                    x: panel.timeToX(panel.time) - width / 2
                    y: -3
                    z: 5
                    width: 2
                    height: parent.height + 6
                    radius: Theme.radiusSmall
                    color: Theme.textPrimary
                    visible: panel.duration > 0
                }
            }

            // ---- Scrub slider -------------------------------------------------------
            Item {
                id: scrub

                anchors.top: lanes.bottom
                anchors.topMargin: Theme.spacingSmall
                width: parent.width
                height: 20

                Rectangle {
                    id: groove
                    x: panel.trackX
                    width: panel.trackWidth
                    height: 5
                    radius: Theme.radiusSmall
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceHigh

                    Rectangle {
                        width: panel.timeToX(panel.time) - panel.trackX
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent
                    }
                }

                Rectangle {
                    x: panel.timeToX(panel.time) - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: panel.handleSize
                    height: panel.handleSize
                    radius: Theme.radiusSmall
                    color: scrubMouse.pressed ? Theme.surfaceHover : Theme.textPrimary
                    border.width: 2
                    border.color: Theme.accent
                    visible: panel.duration > 0
                }

                // Tick labels under the groove.
                Repeater {
                    model: panel.duration > 0 ? Math.floor(panel.span / panel.tickStep) + 1 : 0

                    Text {
                        required property int index
                        readonly property real t: index * panel.tickStep
                        x: panel.timeToX(t) - width / 2
                        y: parent.height + 2
                        text: (panel.tickStep < 1 ? t.toFixed(1) : t.toFixed(0)) + "s"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightBody
                        font.pixelSize: Theme.fontTiny
                    }
                }
            }

        }
    ]
}
