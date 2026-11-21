// MovementPlan.qml
//
// The timeline. This is the single source of truth for execution timing:
// the UI only ever reads and edits blocks through this object, and both the
// validator and the Arduino generator run off the same data.
//
// Every mutation re-validates the whole plan and marks the generated code as
// outdated, so nothing in the UI has to remember to do that.

pragma Singleton
import QtQuick
import "PlanMath.js" as PlanMath
import "Kinematics.js" as Kinematics
import "Validator.js" as Validator
import "ArduinoGenerator.js" as ArduinoGenerator

QtObject {
    id: plan

    // ---- Block storage -------------------------------------------------
    //
    // Roles, all present on every block:
    //   blockId         unique, stable across moves and edits
    //   jointId         "axis1" | "axis2" | "axis3" | "gripper"; "" for a tool move
    //   role            "axis" | "gripper" | "move"
    //   targetAngle     ABSOLUTE target position in degrees
    //   commandId       gripper only: "grip" | "release"
    //   direction       tool move only: "up" | "down" | "left" | "right" |
    //                   "forward" | "back" (robot frame, see Kinematics.js)
    //   distance        tool move only: millimetres to travel that way
    //   startTime       seconds from the start of the sequence
    //   duration        seconds (ignored while naturalDuration is true)
    //   naturalDuration true -> run at the servo's own top speed
    //   invalid         set by revalidate(), drives the red highlight

    readonly property ListModel blocks: ListModel { }

    property int nextBlockId: 1

    // ---- Validation state ----------------------------------------------
    property var validation: ({ ok: true, issues: [], errorCount: 0, warningCount: 0,
                                errorBlockIds: [], warningBlockIds: [], endTime: 0,
                                timeline: null })
    readonly property bool valid: validation.ok
    readonly property var issues: validation.issues
    readonly property int errorCount: validation.errorCount
    readonly property int warningCount: validation.warningCount
    readonly property real endTime: validation.endTime

    readonly property int blockCount: blocks.count

    // Bumped by every mutation. Bind to it (`MovementPlan.revision, expr`) to
    // make a computed value such as effectiveDuration() re-evaluate, since a
    // plain function call has no change notification of its own.
    property int revision: 0

    signal planChanged()

    // Re-validate whenever the hardware configuration changes: mechanical
    // limits and the Axis-2/Axis-3 rule both live in the robot model.
    readonly property Connections configWatcher: Connections {
        target: RobotLibrary
        function onCurrentModelChanged() { plan.touch() }
    }

    // ---- Queries -------------------------------------------------------

    function indexOf(blockId) {
        for (var i = 0; i < blocks.count; ++i) {
            if (blocks.get(i).blockId === blockId)
                return i
        }
        return -1
    }

    function block(blockId) {
        var i = indexOf(blockId)
        return i < 0 ? null : blocks.get(i)
    }

    // Plain-JS copy of the plan, for the validator and the generator.
    function snapshot() {
        var out = []
        for (var i = 0; i < blocks.count; ++i) {
            var b = blocks.get(i)
            out.push({
                blockId: b.blockId,
                jointId: b.jointId,
                role: b.role,
                targetAngle: b.targetAngle,
                commandId: b.commandId,
                direction: b.direction,
                distance: b.distance,
                startTime: b.startTime,
                duration: b.duration,
                naturalDuration: b.naturalDuration,
                rampFraction: b.rampFraction
            })
        }
        return out
    }

    function endTimeOf(blockId) {
        var b = block(blockId)
        return b ? b.startTime + effectiveDuration(blockId) : 0
    }

    // ---- Tool moves ----------------------------------------------------

    function isMove(blockId) {
        var b = block(blockId)
        return !!b && b.role === "move"
    }

    // How the planner resolved a tool move: { ok, reason, axes, from, to,
    // fromAngles, toAngles, duration, deviationMm }, or null for any other
    // block. Straight from the validated timeline.
    function moveInfo(blockId) {
        var tl = validation.timeline
        return tl && tl.moves && tl.moves[blockId] ? tl.moves[blockId] : null
    }

    // Joint ids whose lanes this block occupies: its own axis, or every axis
    // a tool move drives.
    function blockAxes(blockId) {
        var b = block(blockId)
        if (!b)
            return []
        if (b.role === "move")
            return Kinematics.moveAxes(RobotLibrary.currentModel, b.direction)
        return [b.jointId]
    }

    // Earliest moment a new block can start on all of these axes: after
    // everything already planned on any of them.
    function appendTime(jointIds) {
        var tl = validation.timeline
        var latest = 0
        for (var i = 0; tl && i < jointIds.length; ++i) {
            var segs = tl.segments[jointIds[i]]
            for (var s = 0; segs && s < segs.length; ++s)
                latest = Math.max(latest, segs[s].end)
        }
        return latest
    }

    // Duration actually used: either the explicit value or the natural one,
    // which depends on how far this block has to travel. Read from the
    // timeline the validator built, so a block that follows a tool move sees
    // the angles that move really ends on.
    function effectiveDuration(blockId) {
        var b = block(blockId)
        if (!b)
            return 0
        if (b.role === "move") {
            var m = moveInfo(blockId)
            return m ? m.duration : b.duration
        }
        var seg = PlanMath.segmentOf(validation.timeline, blockId, b.jointId)
        return seg ? seg.duration : b.duration
    }

    // Commanded angle of every joint at time t, in `RobotLibrary.joints` order.
    // Reads the timeline the validator already built, so the 3D view shows the
    // exact trajectory that was checked and that the sketch runs (S-curve and
    // per-block ramps included). Bind as `MovementPlan.revision, poseAt(t)`.
    function poseAt(t) {
        var joints = RobotLibrary.joints
        var tl = validation.timeline
        var out = []
        for (var i = 0; i < joints.length; ++i) {
            // Right after a robot switch the timeline can still be the old
            // model's for one binding pass; fall back to the start pose.
            var a = tl ? PlanMath.angleAt(tl, joints[i].id, t) : undefined
            out.push(typeof a === "number" && !isNaN(a) ? a : joints[i].homeAngle)
        }
        return out
    }

    // Per-joint movements for a compact overview: [{ jointId, start, end }].
    function segmentsOf(jointId) {
        var tl = validation.timeline
        return tl && tl.segments[jointId] ? tl.segments[jointId] : []
    }

    // Share of the movement spent accelerating (and again decelerating).
    // Only ramped (S-curve / trapezoid) motion has one; everything else reports 0.
    function rampFraction(blockId) {
        var b = block(blockId)
        if (!b)
            return 0
        return PlanMath.rampOf(b, RobotLibrary.currentModel)
    }

    readonly property bool supportsRamp:
        !!RobotLibrary.currentModel
        && PlanMath.isRamped(RobotLibrary.currentModel.motionProfile)

    // Normalised speed at `progress` (0..1) for a given ramp, using the current
    // robot's motion profile. Lets the ramp editor draw the curve the arm will
    // actually follow rather than an approximation of it.
    function profileVelocity(progress, ramp) {
        return PlanMath.profileVelocity(progress, RobotLibrary.currentModel.motionProfile, ramp)
    }

    // Peak speed and acceleration this block demands of its axis. The stepper
    // generator and the validator both care: asking a stepper for more than it
    // can do does not move it faster, it loses steps.
    function peakDemand(blockId) {
        var b = block(blockId)
        if (!b)
            return { speed: 0, accel: 0, travel: 0, jointId: "" }

        if (b.role === "move") {
            // A tool move is limited by whichever axis it works hardest:
            // report that one, so the ramp editor compares like with like.
            var axes = blockAxes(blockId)
            var worst = { speed: 0, accel: 0, travel: 0, jointId: axes.length ? axes[0] : "" }
            var worstLoad = -1
            for (var i = 0; i < axes.length; ++i) {
                var moveSeg = PlanMath.segmentOf(validation.timeline, blockId, axes[i])
                var joint = RobotLibrary.joint(axes[i])
                if (!moveSeg || !joint)
                    continue
                var p = PlanMath.segmentPeaks(moveSeg, RobotLibrary.currentModel.motionProfile)
                var load = Math.max(
                            joint.maxSpeedDegPerSec ? p.speed / joint.maxSpeedDegPerSec : 0,
                            joint.maxAccelDegPerSec2 && isFinite(p.accel)
                                ? p.accel / joint.maxAccelDegPerSec2 : 0)
                if (load > worstLoad) {
                    worstLoad = load
                    worst = { speed: p.speed, accel: p.accel, travel: p.travel,
                              jointId: axes[i] }
                }
            }
            return worst
        }

        var seg = {
            from: startAngleOf(blockId),
            to: resolvedTarget(blockId),
            duration: effectiveDuration(blockId),
            ramp: rampFraction(blockId)
        }
        return PlanMath.segmentPeaks(seg, RobotLibrary.currentModel.motionProfile)
    }

    function resolvedTarget(blockId) {
        var b = block(blockId)
        if (!b)
            return 0
        var joint = RobotLibrary.joint(b.jointId)
        return PlanMath.targetAngleOf(b, joint)
    }

    // Commanded position of this block's joint at the moment it starts --
    // the home angle, or the target of the previous block on the same joint
    // (which may be a tool move: its derived angle counts like any other).
    function startAngleOf(blockId) {
        var b = block(blockId)
        if (!b)
            return 0
        var joint = RobotLibrary.joint(b.jointId)
        if (!joint)
            return 0
        var seg = PlanMath.segmentOf(validation.timeline, blockId, b.jointId)
        return seg ? seg.from : joint.homeAngle
    }

    // "Up" / "Down" / "Hold", shown on the block cards.
    function directionOf(blockId) {
        var delta = resolvedTarget(blockId) - startAngleOf(blockId)
        if (Math.abs(delta) < 0.05)
            return "hold"
        return delta > 0 ? "up" : "down"
    }

    // ---- Mutation ------------------------------------------------------

    // `targetAngle` is optional. Without it the block picks its own opening
    // target (chooseDefaultTarget); with it -- the 3D view's posing -- it goes
    // where it is told, clamped to the command range like any typed angle.
    function addBlock(jointId, startTime, targetAngle) {
        var joint = RobotLibrary.joint(jointId)
        if (!joint)
            return -1
        var given = targetAngle !== undefined && targetAngle !== null && !isNaN(targetAngle)

        var id = nextBlockId++
        var isGripper = joint.role === "gripper"
        var command = isGripper ? joint.commands[0] : null

        blocks.append({
            blockId: id,
            jointId: jointId,
            role: joint.role,
            targetAngle: isGripper ? command.angle
                                   : (given ? PlanMath.roundTo(
                                                  Math.max(joint.nominalMin,
                                                           Math.min(joint.nominalMax, targetAngle)), 1)
                                            : joint.homeAngle),
            commandId: isGripper ? command.id : "",
            direction: "",
            distance: 0,
            startTime: Math.max(0, startTime),
            duration: 1.0,
            naturalDuration: true,
            rampFraction: RobotLibrary.currentModel.defaultRampFraction !== undefined
                          ? RobotLibrary.currentModel.defaultRampFraction : 0.25,
            invalid: false
        })

        // A gripper block already has somewhere to go; an axis block would
        // otherwise target the position the servo is already in.
        if (!isGripper && !given) {
            // chooseDefaultTarget() reads the validated timeline, which has
            // to know about the new block first.
            revalidate()
            chooseDefaultTarget(id, joint)
        }

        touch()
        return id
    }

    // A tool move: travel `direction` by a distance, from wherever the arm is
    // when the block starts. Opens at 50 mm, or less if the arm has no room
    // for that; if even a short move fails it keeps 50 mm and shows why.
    // `distance` is optional; without it the opening distance is chosen as
    // described above.
    function addMoveBlock(direction, startTime, distance) {
        if (!Kinematics.supports(RobotLibrary.currentModel)
                || !Kinematics.direction(direction))
            return -1
        var given = distance !== undefined && distance !== null && !isNaN(distance)

        var id = nextBlockId++
        blocks.append({
            blockId: id,
            jointId: "",
            role: "move",
            targetAngle: 0,
            commandId: "",
            direction: direction,
            distance: given ? PlanMath.roundTo(Math.max(1, Math.min(maxMoveDistance, distance)), 1)
                            : 50,
            startTime: Math.max(0, startTime),
            duration: 1.0,
            naturalDuration: true,
            rampFraction: RobotLibrary.currentModel.defaultRampFraction !== undefined
                          ? RobotLibrary.currentModel.defaultRampFraction : 0.25,
            invalid: false
        })

        if (!given) {
            var index = indexOf(id)
            var tries = [50, 25, 10]
            for (var i = 0; i < tries.length; ++i) {
                blocks.setProperty(index, "distance", tries[i])
                var solved = PlanMath.build(snapshot(), RobotLibrary.currentModel).moves[id]
                if (solved && solved.ok)
                    break
            }
            if (i === tries.length)
                blocks.setProperty(index, "distance", tries[0])
        }

        touch()
        return id
    }

    // Direction and distance together, in one revalidation: the 3D view's
    // posing flips a move's direction when the drag crosses its start.
    function setMove(blockId, direction, millimetres) {
        var i = indexOf(blockId)
        if (i < 0 || !isMove(blockId) || !Kinematics.direction(direction))
            return
        blocks.setProperty(i, "direction", direction)
        blocks.setProperty(i, "distance",
                           PlanMath.roundTo(Math.max(1, Math.min(maxMoveDistance, millimetres)), 1))
        touch()
    }

    // Earliest moment at or after `t` at which none of these axes is in the
    // middle of a movement, so a block placed there does not fight one
    // already running. (A block that starts later and overlaps is still the
    // validator's to report.)
    function freeTimeFor(jointIds, t) {
        var tl = validation.timeline
        var x = Math.max(0, t)
        if (!tl)
            return x
        for (var pass = 0; pass < 100; ++pass) {
            var moved = false
            for (var i = 0; i < jointIds.length; ++i) {
                var segs = tl.segments[jointIds[i]]
                for (var s = 0; segs && s < segs.length; ++s) {
                    if (segs[s].start <= x + 1e-6 && segs[s].end > x + 1e-6) {
                        x = segs[s].end
                        moved = true
                    }
                }
            }
            if (!moved)
                break
        }
        return x
    }

    // What every axis has been COMMANDED to by time t, in RobotLibrary.joints
    // order: the target of its latest block starting at or before t, even if
    // that block is still running. A block added at t starts from exactly
    // this (PlanMath.build), which is not always the pose on screen at t.
    function commandedPoseAt(t) {
        var joints = RobotLibrary.joints
        var tl = validation.timeline
        var out = []
        for (var i = 0; i < joints.length; ++i) {
            var a = joints[i].homeAngle
            var segs = tl ? tl.segments[joints[i].id] : null
            for (var s = 0; segs && s < segs.length; ++s) {
                if (segs[s].start <= t + 1e-6)
                    a = segs[s].to
            }
            out.push(a)
        }
        return out
    }

    function setMoveDirection(blockId, direction) {
        if (!isMove(blockId) || !Kinematics.direction(direction))
            return
        setProperty(blockId, "direction", direction)
    }

    function setMoveDistance(blockId, millimetres) {
        if (!isMove(blockId))
            return
        var clamped = Math.max(1, Math.min(maxMoveDistance, millimetres))
        setProperty(blockId, "distance", PlanMath.roundTo(clamped, 1))
    }

    // Longest single tool move the inspector offers. Roughly the arm's reach;
    // anything the arm cannot actually do is reported by the validator.
    readonly property real maxMoveDistance: 400

    // Pick an opening target for a freshly created axis block: far enough to be
    // a real movement, and in whichever direction does not break the plan the
    // moment the block lands. Falls back to standing still when neither
    // direction works, rather than inventing an illegal pose.
    function chooseDefaultTarget(blockId, joint) {
        var index = indexOf(blockId)
        var from = startAngleOf(blockId)
        var step = 30

        function errorsWith(angle) {
            blocks.setProperty(index, "targetAngle", PlanMath.roundTo(angle, 1))
            return Validator.validate(snapshot(), RobotLibrary.currentModel).errorCount
        }

        var baseline = errorsWith(from)

        var candidates = []
        var up = Math.min(joint.mechMax, from + step)
        var down = Math.max(joint.mechMin, from - step)
        if (Math.abs(up - from) > 0.5)
            candidates.push(up)
        if (Math.abs(down - from) > 0.5)
            candidates.push(down)

        for (var i = 0; i < candidates.length; ++i) {
            if (errorsWith(candidates[i]) <= baseline)
                return
        }

        errorsWith(from)
    }

    function duplicateBlock(blockId) {
        var b = block(blockId)
        if (!b)
            return -1
        var id = nextBlockId++
        blocks.append({
            blockId: id,
            jointId: b.jointId,
            role: b.role,
            targetAngle: b.targetAngle,
            commandId: b.commandId,
            direction: b.direction,
            distance: b.distance,
            startTime: b.startTime + effectiveDuration(blockId),
            duration: b.duration,
            naturalDuration: b.naturalDuration,
            rampFraction: b.rampFraction,
            invalid: false
        })
        touch()
        return id
    }

    function removeBlock(blockId) {
        var i = indexOf(blockId)
        if (i < 0)
            return
        blocks.remove(i)
        touch()
    }

    function clear() {
        blocks.clear()
        touch()
    }

    function setProperty(blockId, key, value) {
        var i = indexOf(blockId)
        if (i < 0)
            return
        blocks.setProperty(i, key, value)
        touch()
    }

    function setTargetAngle(blockId, angle) {
        var b = block(blockId)
        if (!b)
            return
        var joint = RobotLibrary.joint(b.jointId)
        // Clamp to the servo command range only. Mechanical limits are
        // reported by the validator instead of being silently applied, so the
        // user always sees what they asked for.
        var clamped = Math.max(joint.nominalMin, Math.min(joint.nominalMax, angle))
        setProperty(blockId, "targetAngle", PlanMath.roundTo(clamped, 1))
    }

    function setGripperCommand(blockId, commandId) {
        var b = block(blockId)
        if (!b)
            return
        var cmd = RobotLibrary.gripperCommand(b.jointId, commandId)
        if (!cmd)
            return
        var i = indexOf(blockId)
        blocks.setProperty(i, "commandId", cmd.id)
        blocks.setProperty(i, "targetAngle", cmd.angle)
        touch()
    }

    function setDuration(blockId, seconds) {
        var model = RobotLibrary.currentModel
        var clamped = Math.max(model.minDuration, Math.min(model.maxDuration, seconds))
        var i = indexOf(blockId)
        if (i < 0)
            return
        blocks.setProperty(i, "duration", PlanMath.roundTo(clamped, 2))
        blocks.setProperty(i, "naturalDuration", false)
        touch()
    }

    function setNaturalDuration(blockId, natural) {
        var i = indexOf(blockId)
        if (i < 0)
            return
        if (natural) {
            blocks.setProperty(i, "naturalDuration", true)
        } else {
            // Freeze the current natural length so the block does not jump.
            blocks.setProperty(i, "duration", PlanMath.roundTo(effectiveDuration(blockId), 2))
            blocks.setProperty(i, "naturalDuration", false)
        }
        touch()
    }

    // 0 = start and stop instantly, 0.5 = accelerate to the midpoint then
    // decelerate, never holding a constant speed.
    function setRampFraction(blockId, fraction) {
        var i = indexOf(blockId)
        if (i < 0)
            return
        blocks.setProperty(i, "rampFraction", PlanMath.clampRamp(fraction))
        touch()
    }

    function setStartTime(blockId, seconds) {
        setProperty(blockId, "startTime", PlanMath.roundTo(Math.max(0, seconds), 2))
    }

    // ---- Validation ----------------------------------------------------

    function revalidate() {
        var result = Validator.validate(snapshot(), RobotLibrary.currentModel)
        validation = result

        for (var i = 0; i < blocks.count; ++i) {
            var id = blocks.get(i).blockId
            var bad = result.errorBlockIds.indexOf(id) !== -1
            if (blocks.get(i).invalid !== bad)
                blocks.setProperty(i, "invalid", bad)
        }
        return result
    }

    function issuesForBlock(blockId) {
        var out = []
        for (var i = 0; i < issues.length; ++i) {
            if (issues[i].blockIds.indexOf(blockId) !== -1)
                out.push(issues[i])
        }
        return out
    }

    // Called after every mutation.
    function touch() {
        revalidate()
        revision++
        planChanged()
    }

    // ---- Code generation -----------------------------------------------

    function generateCode() {
        var model = RobotLibrary.currentModel
        var result = revalidate()
        if (!result.ok) {
            return {
                ok: false,
                code: ArduinoGenerator.generateRejection(model, result),
                issues: result.issues
            }
        }
        return {
            ok: true,
            code: ArduinoGenerator.generate(snapshot(), model, result),
            issues: result.issues
        }
    }

    // ---- Demo content --------------------------------------------------

    // A short, valid sequence demonstrating the three things the timeline is
    // for: simultaneous starts, overlapping movements, and a gripper action.
    //
    // Axis-2 and Axis-3 travel together by the same amount, so their spread
    // stays at its home value of 60 deg for the whole move -- which is what
    // keeps the plan inside the 40-140 deg band.
    // Built from whatever axes the selected robot actually has, so it works
    // for any model. Targets come from addBlock(), which already picks a
    // direction that keeps the plan valid -- so the example is correct by
    // construction rather than by hand-tuned numbers.
    function loadExample() {
        blocks.clear()
        nextBlockId = 1

        var model = RobotLibrary.currentModel
        var axes = []
        var grippers = []
        for (var i = 0; i < model.joints.length; ++i) {
            if (model.joints[i].role === "gripper")
                grippers.push(model.joints[i].id)
            else
                axes.push(model.joints[i].id)
        }

        // The first few axes all start at 0 s but run for different lengths:
        // that is what simultaneous-but-independent movement looks like.
        var durations = [6, 10, 8, 9, 7]
        var count = Math.min(3, axes.length)
        for (i = 0; i < count; ++i)
            setDuration(addBlock(axes[i], 0), durations[i])

        // Starts while the others are still travelling -- overlapping motion.
        if (axes.length > 0)
            setDuration(addBlock(axes[0], 7), 3)

        if (grippers.length > 0) {
            var grip = addBlock(grippers[0], 10.5)
            setGripperCommand(grip, "grip")
            setDuration(grip, 1)
        }

        touch()
    }

    Component.onCompleted: revalidate()
}
