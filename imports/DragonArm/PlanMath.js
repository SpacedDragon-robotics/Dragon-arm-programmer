// PlanMath.js
//
// Turns the timeline (a flat list of blocks) into per-joint motion segments.
// Shared by the validator and the Arduino code generator so that what the
// application checks is exactly what it emits.
//
// Every block carries an ABSOLUTE target angle. The starting angle of a
// segment is the joint's commanded position at that moment -- the home angle
// for the first block, otherwise the target of the previous block on the
// same joint.
//
// The exception is a tool-move block (role "move": up / down / left / right /
// forward / back by a distance). It is relative by nature, so its target
// angles are DERIVED here: inverse kinematics from the pose every axis has
// been commanded to when the block starts. It then expands into one ordinary
// segment per axis it drives, which is all the validator, the 3D view and the
// generators ever see.

.pragma library
.import "RobotModels.js" as RobotModels
.import "Kinematics.js" as Kinematics

var EPSILON = 1e-6

function roundTo(value, decimals) {
    var f = Math.pow(10, decimals)
    return Math.round(value * f) / f
}

// Absolute target angle of a block, resolving gripper commands to degrees.
function targetAngleOf(block, joint) {
    if (joint && joint.role === "gripper") {
        var cmd = RobotModels.gripperCommand(joint, block.commandId)
        return cmd ? cmd.angle : block.targetAngle
    }
    return block.targetAngle
}

// -------------------------------------------------------------------------
// Motion profile
//
// Shape of a movement between 0 and 1. The generated sketch implements the
// identical curve, so what the validator checks is exactly what the arm runs.
// Straight-line motion makes an analog servo slam into both ends of a travel;
// smoothstep ramps the speed up and back down instead.
// -------------------------------------------------------------------------
// Ramp fraction is the share of a movement spent accelerating (and the same
// again decelerating). 0 = start and stop instantly, 0.5 = never hold a
// constant speed, just accelerate to the midpoint and slow down again.
var MAX_RAMP = 0.5

function clampRamp(ramp) {
    if (ramp === undefined || ramp === null || isNaN(ramp))
        return 0
    return Math.max(0, Math.min(MAX_RAMP, ramp))
}

// Profiles whose ramp length is set per block.
//   "trapezoid" - speed rises in a straight line: acceleration jumps on and off
//   "scurve"    - speed rises along half a cosine: acceleration itself ramps
//                 up and back down, so there is no jolt at the start or end of
//                 the ramp. Used by the stepper arm.
function isRamped(profile) {
    return profile === "trapezoid" || profile === "scurve"
}

// Steepest acceleration of the ramp relative to a straight ramp of the same
// length. The cosine is steepest in its middle: pi/2 times the average.
function accelShapeFactor(profile) {
    return profile === "scurve" ? Math.PI / 2.0 : 1.0
}

function applyProfile(progress, profile, ramp) {
    if (progress <= 0)
        return 0
    if (progress >= 1)
        return 1

    if (profile === "easeInOut")
        return progress * progress * (3.0 - 2.0 * progress)

    if (profile === "scurve") {
        var rs = clampRamp(ramp)
        if (rs <= 0)
            return progress
        // Same peak as the trapezoid: each cosine ramp averages half the peak
        // speed, exactly like a straight one, so the area works out the same.
        var vs = 1.0 / (1.0 - rs)
        if (progress < rs)
            return vs * (progress / 2.0
                         - (rs / (2.0 * Math.PI)) * Math.sin(Math.PI * progress / rs))
        if (progress <= 1.0 - rs)
            return vs * (rs / 2.0 + (progress - rs))
        var q = 1.0 - progress
        return 1.0 - vs * (q / 2.0 - (rs / (2.0 * Math.PI)) * Math.sin(Math.PI * q / rs))
    }

    if (profile === "trapezoid") {
        var r = clampRamp(ramp)
        if (r <= 0)
            return progress
        // Peak speed that makes the area under the velocity curve exactly 1.
        var peak = 1.0 / (1.0 - r)
        if (progress < r)
            return peak * progress * progress / (2.0 * r)
        if (progress <= 1.0 - r)
            return peak * (r / 2.0 + (progress - r))
        var remaining = 1.0 - progress
        return 1.0 - peak * remaining * remaining / (2.0 * r)
    }

    return progress
}

// How much faster the fastest instant of a movement is than its average.
// A move that must not exceed a top speed has to last this much longer.
function profilePeakFactor(profile, ramp) {
    if (profile === "easeInOut")
        return 1.5                       // smoothstep peaks at 1.5x average
    if (isRamped(profile))
        return 1.0 / (1.0 - clampRamp(ramp))
    return 1.0
}

// Normalised speed (d position / d progress) at a point of the movement.
// The integral over 0..1 is exactly 1. Used to draw the ramp editor, and the
// stepper controller feeds it forward so it does not lag behind the plan.
function profileVelocity(progress, profile, ramp) {
    if (progress <= 0 || progress >= 1)
        return 0
    if (profile === "easeInOut")
        return 6.0 * progress * (1.0 - progress)
    if (!isRamped(profile))
        return 1.0

    var r = clampRamp(ramp)
    if (r <= 0)
        return 1.0
    var peak = 1.0 / (1.0 - r)
    var edge = progress < r ? progress : (progress > 1.0 - r ? 1.0 - progress : -1)
    if (edge < 0)
        return peak                      // cruising
    if (profile === "scurve")
        return peak * (1.0 - Math.cos(Math.PI * edge / r)) / 2.0
    return peak * edge / r
}

// Normalised ACCELERATION of the profile: d2(position)/d(progress)2. Only
// needed for path segments, where a joint's acceleration is the profile's
// own plus whatever the bend of its path adds.
function profileAccel(progress, profile, ramp) {
    if (progress <= 0 || progress >= 1)
        return 0
    if (profile === "easeInOut")
        return 6.0 - 12.0 * progress
    if (!isRamped(profile))
        return 0

    var r = clampRamp(ramp)
    if (r <= 0)
        return 0
    var peak = 1.0 / (1.0 - r)
    var sign = 1.0
    var edge = -1
    if (progress < r) {
        edge = progress
    } else if (progress > 1.0 - r) {
        edge = 1.0 - progress
        sign = -1.0
    }
    if (edge < 0)
        return 0                         // cruising
    if (profile === "scurve")
        return sign * peak * Math.PI / (2.0 * r) * Math.sin(Math.PI * edge / r)
    return sign * peak / r
}

// -------------------------------------------------------------------------
// Path segments
//
// A tool move gives each axis a path instead of a plain from/to (see
// Kinematics.js). Its position is path(applyProfile(progress)): the profile
// says how far along the line the tool is, the path says what angle that
// takes. Speed and acceleration then depend on the bend of the path as well
// as on the profile, so they are measured rather than derived from a formula.
// -------------------------------------------------------------------------

// Peak speed and acceleration of a path run in exactly one second. Speed
// scales with 1/duration and acceleration with 1/duration^2.
function pathUnitPeaks(path, profile, ramp) {
    var r = isRamped(profile) ? clampRamp(ramp) : 0
    var speed = 0
    var accel = 0

    // This runs for every axis of every tool move on every edit, so it takes
    // the spline's slope and curvature from one set of coefficients.
    function probe(p) {
        var v = profileVelocity(p, profile, ramp)
        var a = profileAccel(p, profile, ramp)
        var q = Kinematics.pathCubic(path, applyProfile(p, profile, ramp))
        var slope = ((3.0 * q.a * q.t + 2.0 * q.b) * q.t + q.c) * q.n
        var curve = (6.0 * q.a * q.t + 2.0 * q.b) * q.n * q.n
        speed = Math.max(speed, Math.abs(slope * v))
        accel = Math.max(accel, Math.abs(curve * v * v + slope * a))
    }

    var i
    for (i = 0; i <= 96; ++i)
        probe(i / 96.0)
    // The ramps are where the profile's own acceleration lives; a short ramp
    // would otherwise fall between the samples above.
    for (i = 1; r > 0 && i < 24; ++i) {
        probe(r * i / 24.0)
        probe(1.0 - r * i / 24.0)
    }

    var travel = 0
    for (i = 1; i < path.length; ++i)
        travel += Math.abs(path[i] - path[i - 1])

    // Instant start: infinite acceleration, exactly as for a plain segment.
    if (isRamped(profile) && r <= 0 && travel > 1e-6)
        accel = Infinity
    return { speed: speed, accel: accel, travel: travel }
}

// Shortest time a path can take within the axis's limits. `unit` is the
// result of pathUnitPeaks() when the caller already has it.
function pathNaturalDuration(model, joint, path, ramp, unit) {
    if (!unit)
        unit = pathUnitPeaks(path, model.motionProfile, ramp)
    var topSpeed, topAccel

    if (model.driveType === "stepper") {
        topSpeed = joint && joint.maxSpeedDegPerSec ? joint.maxSpeedDegPerSec : 60
        topAccel = joint && joint.maxAccelDegPerSec2 ? joint.maxAccelDegPerSec2 : 120
    } else {
        topSpeed = 60.0 / Math.max(model.naturalSecondsPer60Deg, 1e-6)
        topAccel = Infinity
    }

    var seconds = unit.speed / Math.max(topSpeed, 1e-6)
    if (isFinite(unit.accel) && isFinite(topAccel))
        seconds = Math.max(seconds, Math.sqrt(unit.accel / Math.max(topAccel, 1e-6)))

    // Round UP, never down (see naturalDuration).
    seconds = Math.ceil(seconds * 1000) / 1000
    return Math.max(model.minDuration, seconds)
}

// Shortest duration that keeps a segment inside its axis's limits, whichever
// kind of segment it is.
function segmentMinDuration(model, joint, seg) {
    if (seg.path)
        return pathNaturalDuration(model, joint, seg.path, seg.ramp)
    return naturalDuration(model, joint, seg.from, seg.to, seg.ramp)
}

// Ramp fraction a block actually uses. Only ramped profiles have one.
function rampOf(block, model) {
    if (!model || !isRamped(model.motionProfile))
        return 0
    if (block && block.rampFraction !== undefined)
        return clampRamp(block.rampFraction)
    return clampRamp(model.defaultRampFraction)
}

// Shortest time this travel can take without exceeding the hardware's limits.
//
// For a servo that is "as fast as the servo goes" -- a plain servo.write().
// For a stepper it is the axis's own top speed, which is a hard limit: ask for
// less time than this and the driver will simply lose steps.
function naturalDuration(model, joint, fromAngle, toAngle, ramp) {
    var travel = Math.abs(toAngle - fromAngle)
    var seconds

    if (model.driveType === "stepper") {
        var peakFactor = profilePeakFactor(model.motionProfile, ramp)
        var topSpeed = joint && joint.maxSpeedDegPerSec ? joint.maxSpeedDegPerSec : 60
        var topAccel = joint && joint.maxAccelDegPerSec2 ? joint.maxAccelDegPerSec2 : 120

        // Fast enough to respect the top speed...
        seconds = travel * peakFactor / Math.max(topSpeed, 1e-6)

        // ...but also gentle enough to respect the acceleration limit. Peak
        // acceleration is travel*peakFactor / (ramp * duration^2), so solving
        // for duration gives the floor below. Ignoring this was letting the
        // app propose movements the motor could not actually ramp into.
        var r = clampRamp(ramp)
        if (r > 0) {
            var accelFloor = Math.sqrt(travel * peakFactor * accelShapeFactor(model.motionProfile)
                                       / (r * Math.max(topAccel, 1e-6)))
            if (accelFloor > seconds)
                seconds = accelFloor
        }

        // Round UP, never down: rounding to nearest can shave a duration just
        // under a limit the validator then rejects.
        seconds = Math.ceil(seconds * 1000) / 1000
        return Math.max(model.minDuration, seconds)
    } else {
        seconds = (travel / 60.0) * model.naturalSecondsPer60Deg
        seconds *= profilePeakFactor(model.motionProfile, ramp)
    }

    return Math.max(model.minDuration, roundTo(seconds, 3))
}

function effectiveDuration(block, model, joint, fromAngle, toAngle) {
    var ramp = rampOf(block, model)
    if (block.naturalDuration)
        return naturalDuration(model, joint, fromAngle, toAngle, ramp)
    return Math.max(model.minDuration, block.duration)
}

// Peak speed and acceleration a segment demands, in degrees per second.
// Used by the validator to reject plans a stepper cannot physically follow.
function segmentPeaks(seg, profile) {
    var duration = Math.max(seg.duration, 1e-6)

    if (seg.path) {
        // build() measured the path once already; measuring is the costly part.
        var unit = seg.unitPeaks ? seg.unitPeaks : pathUnitPeaks(seg.path, profile, seg.ramp)
        return { speed: unit.speed / duration,
                 accel: unit.accel / (duration * duration),
                 travel: unit.travel }
    }

    var travel = Math.abs(seg.to - seg.from)
    var peakSpeed = (travel / duration) * profilePeakFactor(profile, seg.ramp)

    var peakAccel = 0
    if (isRamped(profile)) {
        var r = clampRamp(seg.ramp)
        // Instant reversal at r = 0 would be infinite acceleration; report it
        // as such so the validator can flag it rather than divide by zero.
        peakAccel = r > 0 ? peakSpeed * accelShapeFactor(profile) / (r * duration) : Infinity
    } else if (profile === "easeInOut") {
        // Smoothstep: |a|max = 6 * travel / duration^2
        peakAccel = 6.0 * travel / (duration * duration)
    }

    return { speed: peakSpeed, accel: peakAccel, travel: travel }
}

// -------------------------------------------------------------------------
// build()
//
// Returns
//   segments   { jointId: [ { blockId, jointId, start, end, from, to } ] }
//   overlaps   [ { jointId, blockIds } ]  two blocks fighting over one servo
//   moves      { blockId: { ok, reason, axes, from, to, fromAngles, toAngles,
//                duration, deviationMm } }  how each tool-move block resolved
//   endTime    last moment at which anything is still moving
//   homeAngles { jointId: degrees }
// -------------------------------------------------------------------------
function isMoveBlock(block) {
    return !!block && block.role === "move"
}

function build(blocks, model) {
    var segments = {}
    var homeAngles = {}
    var commanded = {}      // latest commanded angle of every joint
    var previous = {}       // last segment emitted on every joint
    var overlaps = []
    var moves = {}
    var endTime = 0
    var canMove = Kinematics.supports(model)
    var i

    for (i = 0; i < model.joints.length; ++i) {
        var id = model.joints[i].id
        segments[id] = []
        homeAngles[id] = model.joints[i].homeAngle
        commanded[id] = model.joints[i].homeAngle
        previous[id] = null
    }

    // One chronological pass over the whole plan, not one per joint: a tool
    // move starts from wherever EVERY axis has been commanded to by then.
    // Ties are broken by creation order so the result never depends on
    // ListModel iteration order.
    var ordered = []
    for (i = 0; i < blocks.length; ++i) {
        var b = blocks[i]
        if (isMoveBlock(b) ? canMove : segments[b.jointId] !== undefined)
            ordered.push(b)     // else: a block the current model cannot run
    }
    ordered.sort(function (a, b) {
        if (Math.abs(a.startTime - b.startTime) > EPSILON)
            return a.startTime - b.startTime
        return a.blockId - b.blockId
    })

    function emit(block, jointId, target, duration, ramp, path, unitPeaks) {
        var seg = {
            blockId: block.blockId,
            jointId: jointId,
            start: roundTo(block.startTime, 3),
            end: roundTo(block.startTime + duration, 3),
            duration: roundTo(duration, 3),
            from: commanded[jointId],
            to: target,
            // Carried per segment: the ramp is a per-block setting, so the
            // trajectory the validator sweeps is the one the arm runs.
            ramp: ramp
        }
        // Tool moves only: the curve this axis follows between from and to,
        // so the tool travels in a straight line (Kinematics.js).
        if (path) {
            seg.path = path
            seg.unitPeaks = unitPeaks
        }

        // One servo cannot follow two targets at once.
        var before = previous[jointId]
        if (before && seg.start < before.end - EPSILON) {
            overlaps.push({
                jointId: jointId,
                blockIds: [before.blockId, seg.blockId]
            })
        }

        segments[jointId].push(seg)
        commanded[jointId] = target
        previous[jointId] = seg
        endTime = Math.max(endTime, seg.end)
    }

    for (i = 0; i < ordered.length; ++i) {
        var block = ordered[i]
        var ramp = rampOf(block, model)
        var duration

        if (!isMoveBlock(block)) {
            var joint = RobotModels.findJoint(model, block.jointId)
            var target = targetAngleOf(block, joint)
            duration = effectiveDuration(block, model, joint, commanded[block.jointId],
                                         target)
            emit(block, block.jointId, target, duration, ramp)
            continue
        }

        // A tool move becomes one segment per axis it drives. They all start
        // together, take the same time and share one profile, so at every
        // instant each axis is at the same point of the line.
        var solved = Kinematics.solveMove(model, commanded, block.direction, block.distance)
        var paths = solved.ok ? solved.paths : {}
        var fromPose = {}
        var toPose = {}
        var k
        for (var jid in commanded) {
            fromPose[jid] = commanded[jid]
            toPose[jid] = solved.targets[jid] !== undefined ? solved.targets[jid]
                                                            : commanded[jid]
        }

        // Speed and acceleration each path demands, measured once and kept
        // on the segment for the validator.
        var unit = {}
        for (k = 0; k < solved.axes.length; ++k) {
            if (paths[solved.axes[k]])
                unit[solved.axes[k]] = pathUnitPeaks(paths[solved.axes[k]],
                                                     model.motionProfile, ramp)
        }

        if (block.naturalDuration) {
            // As fast as the slowest axis allows.
            duration = model.minDuration
            for (k = 0; k < solved.axes.length; ++k) {
                var axisId = solved.axes[k]
                if (paths[axisId]) {
                    duration = Math.max(duration, pathNaturalDuration(
                                            model, RobotModels.findJoint(model, axisId),
                                            paths[axisId], ramp, unit[axisId]))
                }
            }
        } else {
            duration = Math.max(model.minDuration, block.duration)
        }

        moves[block.blockId] = {
            ok: solved.ok,
            code: solved.ok ? "" : solved.code,
            reason: solved.ok ? "" : solved.reason,
            axes: solved.axes,
            from: solved.from,
            to: solved.to,
            fromAngles: fromPose,
            toAngles: toPose,
            duration: roundTo(duration, 3),
            // Worst distance between the tool and its place on the line.
            deviationMm: solved.ok ? Kinematics.pathDeviation(model, fromPose, paths,
                                                              solved.from, solved.to) : 0
        }

        for (k = 0; k < solved.axes.length; ++k)
            emit(block, solved.axes[k], solved.targets[solved.axes[k]], duration, ramp,
                 paths[solved.axes[k]], unit[solved.axes[k]])
    }

    return {
        segments: segments,
        overlaps: overlaps,
        moves: moves,
        endTime: roundTo(endTime, 3),
        homeAngles: homeAngles,
        motionProfile: model.motionProfile
    }
}

// The segment a block produced on one joint, or null.
function segmentOf(timeline, blockId, jointId) {
    var segs = timeline && timeline.segments ? timeline.segments[jointId] : null
    if (!segs)
        return null
    for (var i = 0; i < segs.length; ++i) {
        if (segs[i].blockId === blockId)
            return segs[i]
    }
    return null
}

// Commanded angle of one joint at time t, interpolated across its segments.
function angleAt(timeline, jointId, t) {
    var segs = timeline.segments[jointId]
    var angle = timeline.homeAngles[jointId]
    if (!segs)
        return angle

    for (var i = 0; i < segs.length; ++i) {
        var s = segs[i]
        if (t <= s.start + EPSILON)
            break
        if (t >= s.end - EPSILON) {
            angle = s.to           // finished: hold the target
            continue
        }
        var progress = (t - s.start) / Math.max(s.duration, EPSILON)
        var shaped = applyProfile(progress, timeline.motionProfile, s.ramp)
        angle = s.path ? Kinematics.pathAngle(s.path, shaped)
                       : s.from + (s.to - s.from) * shaped
        break
    }
    return angle
}

// Segment of `jointId` that is running at time t, or null.
function activeSegment(timeline, jointId, t) {
    var segs = timeline.segments[jointId]
    if (!segs)
        return null
    for (var i = 0; i < segs.length; ++i) {
        if (t >= segs[i].start - EPSILON && t <= segs[i].end + EPSILON)
            return segs[i]
    }
    return null
}

// Last segment of `jointId` that has already finished at time t, or null.
function lastFinishedSegment(timeline, jointId, t) {
    var segs = timeline.segments[jointId]
    var found = null
    if (!segs)
        return null
    for (var i = 0; i < segs.length; ++i) {
        if (segs[i].end <= t + EPSILON)
            found = segs[i]
    }
    return found
}

// Every moment where the motion of any joint changes character, plus a fine
// uniform grid. Constraints are evaluated on this set, so both the corners of
// the motion profile and the middle of long travels are covered.
function sampleTimes(timeline, step, endPadding) {
    var times = [0]
    var jointId, segs, i

    for (jointId in timeline.segments) {
        segs = timeline.segments[jointId]
        for (i = 0; i < segs.length; ++i) {
            times.push(segs[i].start)
            times.push(segs[i].end)
        }
    }

    var end = timeline.endTime + (endPadding === undefined ? 0 : endPadding)
    for (var t = 0; t <= end; t += step)
        times.push(roundTo(t, 4))
    times.push(roundTo(end, 4))

    times.sort(function (a, b) { return a - b })

    var unique = []
    for (i = 0; i < times.length; ++i) {
        if (times[i] < -EPSILON)
            continue
        if (unique.length === 0 || Math.abs(times[i] - unique[unique.length - 1]) > 1e-4)
            unique.push(times[i])
    }
    return unique
}

// All blocks that are moving, or have most recently moved, a given joint at t.
// Used to attribute a constraint violation to concrete blocks.
function responsibleBlockIds(timeline, jointIds, t) {
    var ids = []
    for (var i = 0; i < jointIds.length; ++i) {
        var seg = activeSegment(timeline, jointIds[i], t)
        if (!seg)
            seg = lastFinishedSegment(timeline, jointIds[i], t)
        if (seg && ids.indexOf(seg.blockId) === -1)
            ids.push(seg.blockId)
    }
    return ids
}
