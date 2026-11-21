// View3DModule.qml
//
// Plays the movement plan back on the robot's 3D model:
//   centre  the model, orbitable (RobotViewport)
//   bottom  a simplified timeline with a scrub slider (PlaybackPanel)
//
// The pose shown at any moment comes from MovementPlan.poseAt(), which reads
// the very timeline the validator checked -- same S-curve, same per-block
// ramps -- so what you see is what the generated sketch commands. It starts
// from each axis's "Plan start" angle; the real arm starts from wherever its
// encoders say it is.
//
// Playback state lives here, not in AppState: nothing outside this module
// needs it, and the module is kept alive while the user navigates away.
//
// Posing (PoseController turns the mouse into an angle or a distance; this
// file turns that into blocks), pose-to-pose as in animation software:
//   * A drag starts a new step AT THE PLAYHEAD -- later if the axes it needs
//     are still busy then -- and the playhead follows the step's end, so
//     the model shows the pose being made. Release, and the next drag
//     starts from there: pose, pose, pose builds a sequence.
//   * Dragging the same axis (or the tool along the same line) again before
//     touching the playhead refines that step instead of adding a new one.
//   * Shift-drag a segment: start together with the last step, so several
//     axes move at once. Tool moves always get a step of their own -- they
//     drive nearly every axis.
//   * Esc cancels the drag in progress; a drag that ends where it started
//     removes its block. Delete removes the selected block.
// Every change goes through MovementPlan, so the validator, the Blocks
// timeline and the generated sketch see each pose the moment it is made.

import QtQuick
import DragonArm
import "../common"

Item {
    id: module

    property real time: 0
    property bool playing: false
    property bool looping: false
    property real speed: 1.0

    readonly property real duration: MovementPlan.endTime
    readonly property var pose: (MovementPlan.revision, MovementPlan.poseAt(time))

    function togglePlay() {
        if (duration <= 0)
            return
        if (!playing && time >= duration - 1e-3)
            time = 0
        playing = !playing
    }

    function restart() {
        time = 0
    }

    function seek(t) {
        time = Math.max(0, Math.min(duration, t))
    }

    // ---- Posing session ---------------------------------------------------

    // Last block the 3D view made or refined, and the playhead it left.
    property int lastPoseBlockId: -1
    property real lastPoseTime: -1
    property var session: null
    property var pendingPose: undefined
    // Shown next to the cursor while dragging.
    property string poseStatus: ""
    property string poseNote: ""

    // Robot axis -> the two tool-move directions along it, positive first.
    readonly property var toolPairs: [["forward", "back"], ["left", "right"], ["up", "down"]]

    function directionFor(axis, signed) {
        return toolPairs[axis][signed >= 0 ? 0 : 1]
    }

    function axisOfDirection(direction) {
        for (var k = 0; k < toolPairs.length; ++k) {
            if (toolPairs[k].indexOf(direction) !== -1)
                return k
        }
        return -1
    }

    function signedDistanceOf(b) {
        var k = axisOfDirection(b.direction)
        return (k >= 0 && toolPairs[k][0] === b.direction ? 1 : -1) * b.distance
    }

    function showTime(t) {
        time = Math.max(0, Math.min(duration, t))
    }

    // kind "axis": key = joint id. kind "tool": key = robot axis 0/1/2.
    // Returns { origin } -- for a tool move, the robot-frame point its
    // straight line starts from.
    function beginPose(kind, key, together) {
        playing = false
        poseStatus = ""
        poseNote = ""
        pendingPose = undefined

        var last = lastPoseBlockId >= 0 ? MovementPlan.block(lastPoseBlockId) : null
        var refine = !!last && Math.abs(time - lastPoseTime) < 1e-6
                && (kind === "axis" ? last.role !== "move" && last.jointId === key
                                    : last.role === "move" && axisOfDirection(last.direction) === key)

        var s = { kind: kind, key: key, blockId: -1, created: false, original: null,
                  baseSigned: 0, start: time, timeAtPress: time, lastGood: null, still: false }

        if (refine) {
            s.blockId = lastPoseBlockId
            s.start = last.startTime
            s.original = { targetAngle: last.targetAngle, direction: last.direction,
                           distance: last.distance }
            if (kind === "tool") {
                s.baseSigned = signedDistanceOf(last)
                s.lastGood = { direction: last.direction, distance: last.distance }
            }
        } else {
            var axes = kind === "axis" ? [key] : RobotLibrary.moveAxes(directionFor(key, 1))
            var start = time
            if (together && last && kind === "axis")
                start = last.startTime
            start = MovementPlan.freeTimeFor(axes, start)
            // Show the pose the move will actually start from.
            if (start > time + 1e-6)
                showTime(start)
            s.start = start
            s.timeAtPress = time
        }
        session = s

        var origin = null
        if (kind === "tool") {
            var m = refine ? MovementPlan.moveInfo(s.blockId) : null
            origin = m ? m.from : RobotLibrary.toolPoint(MovementPlan.commandedPoseAt(s.start))
        }
        return { origin: origin }
    }

    // Axis: the absolute angle. Tool: millimetres along the axis since the
    // press. Coalesced: one plan update per event-loop pass, however fast the
    // mouse reports.
    function updatePose(value) {
        if (!session)
            return
        var first = pendingPose === undefined
        pendingPose = value
        if (first)
            Qt.callLater(applyPose)
    }

    function applyPose() {
        var s = session
        if (!s || pendingPose === undefined)
            return
        var value = pendingPose
        pendingPose = undefined

        if (s.kind === "axis") {
            var joint = RobotLibrary.joint(s.key)
            var angle = Math.round(value * 2) / 2
            if (s.blockId < 0) {
                s.blockId = MovementPlan.addBlock(s.key, s.start, angle)
                s.created = true
            } else if (Math.abs(MovementPlan.block(s.blockId).targetAngle - angle) > 1e-6) {
                MovementPlan.setTargetAngle(s.blockId, angle)
            }
            poseStatus = joint.name + "  " + angle.toFixed(1) + "°"
        } else {
            var signed = s.baseSigned + Math.round(value)
            var direction = directionFor(s.key, signed)
            var distance = Math.abs(signed)
            s.still = distance < 1
            if (s.still) {
                poseStatus = RobotLibrary.moveLabel(direction) + "  0 mm"
                return
            }

            if (s.blockId < 0) {
                var id = MovementPlan.addMoveBlock(direction, s.start, distance)
                var made = MovementPlan.moveInfo(id)
                if (!made || !made.ok) {
                    // Not even this much is possible from here: say why, and
                    // leave nothing behind.
                    poseNote = made ? made.reason : ""
                    MovementPlan.removeBlock(id)
                    return
                }
                s.blockId = id
                s.created = true
            } else {
                MovementPlan.setMove(s.blockId, direction, distance)
                var info = MovementPlan.moveInfo(s.blockId)
                if (!info || !info.ok) {
                    // Stop at the last reachable point, and say what is in
                    // the way. What is on screen is what gets kept.
                    poseNote = info ? info.reason : ""
                    if (s.lastGood)
                        MovementPlan.setMove(s.blockId, s.lastGood.direction, s.lastGood.distance)
                    showTime(Math.max(s.timeAtPress, MovementPlan.endTimeOf(s.blockId)))
                    return
                }
            }
            s.lastGood = { direction: direction, distance: distance }
            poseNote = ""
            poseStatus = RobotLibrary.moveLabel(direction) + "  " + distance.toFixed(0) + " mm"
        }

        lastPoseBlockId = s.blockId
        // Follow the move to its end, so the model shows the pose being set.
        showTime(Math.max(s.timeAtPress, MovementPlan.endTimeOf(s.blockId)))
    }

    function endPose() {
        applyPose()
        var s = session
        session = null
        pendingPose = undefined
        poseStatus = ""
        poseNote = ""
        if (!s || s.blockId < 0 || MovementPlan.indexOf(s.blockId) < 0)
            return

        var b = MovementPlan.block(s.blockId)
        var still = s.kind === "axis"
                ? Math.abs(b.targetAngle - MovementPlan.startAngleOf(s.blockId)) < 0.25
                : s.still
        if (still) {
            // Dragged back to where it started: no movement, no block.
            MovementPlan.removeBlock(s.blockId)
            lastPoseBlockId = -1
            lastPoseTime = -1
            showTime(s.timeAtPress)
            return
        }

        showTime(Math.max(s.timeAtPress, MovementPlan.endTimeOf(s.blockId)))
        lastPoseBlockId = s.blockId
        lastPoseTime = time
        AppState.selectBlock(s.blockId)
    }

    function cancelPose() {
        var s = session
        session = null
        pendingPose = undefined
        poseStatus = ""
        poseNote = ""
        if (!s)
            return
        if (s.created && s.blockId >= 0) {
            MovementPlan.removeBlock(s.blockId)
        } else if (s.original && s.blockId >= 0) {
            if (s.kind === "axis")
                MovementPlan.setTargetAngle(s.blockId, s.original.targetAngle)
            else
                MovementPlan.setMove(s.blockId, s.original.direction, s.original.distance)
        }
        showTime(s.timeAtPress)
    }

    // Wall-clock driven, so playback runs at real speed whatever the frame rate.
    FrameAnimation {
        running: module.playing && module.visible
        onTriggered: {
            var t = module.time + frameTime * module.speed
            if (t >= module.duration) {
                if (module.looping && module.duration > 0) {
                    t = t % module.duration
                } else {
                    t = module.duration
                    module.playing = false
                }
            }
            module.time = t
        }
    }

    // A shorter plan, or a different robot, must not leave the playhead
    // stranded past the end.
    onDurationChanged: {
        if (time > duration)
            time = duration
        if (duration <= 0)
            playing = false
    }

    Connections {
        target: RobotLibrary
        function onModelReplaced() {
            module.playing = false
            module.time = 0
            module.session = null
            module.lastPoseBlockId = -1
            module.lastPoseTime = -1
        }
    }

    focus: visible
    Keys.onSpacePressed: function (event) {
        module.togglePlay()
        event.accepted = true
    }
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Home) {
            module.restart()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape && module.session) {
            viewport.cancelPose()
            event.accepted = true
        } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
                   && !module.session && AppState.selectedBlockId !== -1) {
            module.deleteSelected()
            event.accepted = true
        }
    }

    // Delete key, or the button on the playback panel. The playhead goes to
    // where the block started, which is where the next pose would go.
    function deleteSelected() {
        var b = MovementPlan.block(AppState.selectedBlockId)
        if (!b || session)
            return
        var start = b.startTime
        MovementPlan.removeBlock(AppState.selectedBlockId)
        showTime(start)
        lastPoseBlockId = -1
        lastPoseTime = -1
    }

    // ---- Model ------------------------------------------------------------
    RobotViewport {
        id: viewport

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: playback.top
        anchors.margins: Theme.spacing
        pose: module.pose
        poseTarget: module
    }

    // ---- Simplified timeline ---------------------------------------------
    PlaybackPanel {
        id: playback

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing
        height: implicitHeight

        time: module.time
        duration: module.duration
        playing: module.playing
        looping: module.looping
        speed: module.speed

        onPlayToggled: module.togglePlay()
        onRestartRequested: module.restart()
        onSeekRequested: function (t) { module.seek(t) }
        onLoopToggled: module.looping = !module.looping
        onSpeedPicked: function (s) { module.speed = s }
        onDeleteRequested: module.deleteSelected()
    }
}
