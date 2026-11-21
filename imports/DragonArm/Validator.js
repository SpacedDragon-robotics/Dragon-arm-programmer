// Validator.js
//
// Checks a complete movement plan against the selected robot model.
//
// The Axis-2 / Axis-3 rule is NOT a per-block check: two individually legal
// blocks can still drive the arm through an illegal pose while both servos are
// travelling. The validator therefore samples the commanded trajectory of
// every joint across the whole timeline -- including simultaneous movements and
// the transitions between timeline states -- and reports the time windows in
// which a constraint is broken.
//
// The validator never modifies the user's target angles. It only reports.

.pragma library
.import "RobotModels.js" as RobotModels
.import "PlanMath.js" as PlanMath
.import "Kinematics.js" as Kinematics

var SAMPLE_STEP = 0.02      // seconds between constraint samples
var HOLD_PADDING = 0.25     // also check a moment after the last movement

function issue(severity, code, title, message, hint, blockIds, time) {
    return {
        severity: severity,
        code: code,
        title: title,
        message: message,
        hint: hint === undefined ? "" : hint,
        blockIds: blockIds === undefined ? [] : blockIds,
        time: time === undefined ? -1 : time
    }
}

function fmt(v) {
    return PlanMath.roundTo(v, 1).toFixed(1)
}

// -------------------------------------------------------------------------
// Per-block parameter checks
// -------------------------------------------------------------------------
// Start time and duration rules are the same for every kind of block.
function checkTiming(b, label, model, issues) {
    if (b.startTime < -1e-6) {
        issues.push(issue("error", "negative-start", label + ": negative start time",
                          "A block cannot start before 0 s.",
                          "Drag the block back onto the timeline.", [b.blockId]))
    }

    if (!b.naturalDuration) {
        if (isNaN(b.duration) || b.duration <= 0) {
            issues.push(issue("error", "bad-duration", label + ": invalid duration",
                              "Duration must be greater than zero.",
                              "Set a duration or switch the block to natural speed.",
                              [b.blockId]))
        } else if (b.duration > model.maxDuration + 1e-6) {
            issues.push(issue("warning", "long-duration", label + ": very long movement",
                              "Duration " + fmt(b.duration) + " s exceeds the configured maximum of "
                              + fmt(model.maxDuration) + " s.",
                              "Shorten the movement or raise the limit in the robot model.",
                              [b.blockId]))
        }
    }
}

function moveLabel(b) {
    var d = Kinematics.direction(b.direction)
    return "Move " + (d ? d.name.toLowerCase() : "tool")
}

function checkBlocks(blocks, model, issues) {
    for (var i = 0; i < blocks.length; ++i) {
        var b = blocks[i]

        if (PlanMath.isMoveBlock(b)) {
            if (!Kinematics.supports(model)) {
                issues.push(issue("error", "no-kinematics", "Tool move not available",
                                  model.name + " has no geometry description, so the app "
                                  + "cannot work out which angles move its tool in a "
                                  + "straight direction.",
                                  "Delete the block or switch to a robot model that "
                                  + "supports tool moves.",
                                  [b.blockId]))
                continue
            }
            if (!Kinematics.direction(b.direction)) {
                issues.push(issue("error", "bad-direction", "Tool move: unknown direction",
                                  "\"" + b.direction + "\" is not a direction.",
                                  "Pick a direction in the block inspector.", [b.blockId]))
            }
            if (isNaN(b.distance) || b.distance <= 0) {
                issues.push(issue("error", "bad-distance", moveLabel(b) + ": no distance",
                                  "The distance must be greater than zero.",
                                  "Set a distance in the block inspector.", [b.blockId]))
            }
            checkTiming(b, moveLabel(b), model, issues)
            continue
        }

        var joint = RobotModels.findJoint(model, b.jointId)

        if (!joint) {
            issues.push(issue("error", "unknown-joint", "Unknown axis",
                              "This block targets \"" + b.jointId + "\", which does not exist on "
                              + model.name + ".",
                              "Delete the block or switch back to a robot model that has this axis.",
                              [b.blockId]))
            continue
        }

        if (joint.role === "gripper") {
            var cmd = RobotModels.gripperCommand(joint, b.commandId)
            if (!cmd) {
                issues.push(issue("error", "bad-command", joint.name + ": unknown command",
                                  "The gripper command \"" + b.commandId + "\" is not defined.",
                                  "Pick Grip or Release in the block inspector.",
                                  [b.blockId]))
                continue
            }
        }

        var target = PlanMath.targetAngleOf(b, joint)

        if (isNaN(target)) {
            issues.push(issue("error", "bad-angle", joint.name + ": missing angle",
                              "The target angle is not a number.", "Enter a value between "
                              + fmt(joint.mechMin) + "° and " + fmt(joint.mechMax) + "°.",
                              [b.blockId]))
        } else if (target < joint.nominalMin - 1e-6 || target > joint.nominalMax + 1e-6) {
            issues.push(issue("error", "angle-out-of-servo-range",
                              joint.name + ": outside servo range",
                              "Target " + fmt(target) + "° is outside the MG996R command range "
                              + fmt(joint.nominalMin) + "°–" + fmt(joint.nominalMax) + "°.",
                              "Clamp the angle into the servo range.",
                              [b.blockId]))
        } else if (target < joint.mechMin - 1e-6 || target > joint.mechMax + 1e-6) {
            issues.push(issue("error", "angle-out-of-mech-range",
                              joint.name + ": outside mechanical limits",
                              "Target " + fmt(target) + "° exceeds the mechanical limits of "
                              + joint.name + " (" + fmt(joint.mechMin) + "°–"
                              + fmt(joint.mechMax) + "°).",
                              "Change the angle, or widen the limits in Robot Model → Hardware.",
                              [b.blockId]))
        }

        checkTiming(b, joint.name, model, issues)
    }
}

// -------------------------------------------------------------------------
// Tool moves that have no solution
//
// A move the arm cannot make is reported, never shortened: quietly stopping
// at the edge of the reach would leave every later move starting from a place
// the user did not ask for.
// -------------------------------------------------------------------------
function checkMoves(blocks, timeline, model, issues) {
    for (var i = 0; i < blocks.length; ++i) {
        var b = blocks[i]
        var m = PlanMath.isMoveBlock(b) ? timeline.moves[b.blockId] : null
        if (!m || m.ok || m.code === "bad-direction")
            continue
        if (isNaN(b.distance) || b.distance <= 0)
            continue        // already reported by checkBlocks

        issues.push(issue("error", "move-unreachable",
                          moveLabel(b) + " " + fmt(b.distance) + " mm: out of reach",
                          "The tool would have to go from (" + fmt(m.from.x) + ", "
                          + fmt(m.from.y) + ", " + fmt(m.from.z) + ") to (" + fmt(m.to.x)
                          + ", " + fmt(m.to.y) + ", " + fmt(m.to.z) + ") mm, but "
                          + m.reason + ".",
                          "Shorten the distance, or first bring the arm to a pose with "
                          + "more room in that direction.",
                          [b.blockId], b.startTime))
    }
}

// -------------------------------------------------------------------------
// Stepper motion limits
//
// A servo asked to move faster than it can simply lags. A stepper asked to
// move faster than it can LOSES STEPS, and open-loop position is then wrong
// for the rest of the sequence. So for stepper arms this is an error, not a
// warning -- it is the difference between a slow arm and a wrong one.
// -------------------------------------------------------------------------
function checkStepperLimits(timeline, model, issues) {
    if (model.driveType !== "stepper")
        return

    for (var jointId in timeline.segments) {
        var joint = RobotModels.findJoint(model, jointId)
        var segs = timeline.segments[jointId]

        for (var i = 0; i < segs.length; ++i) {
            var seg = segs[i]
            if (seg.duration <= 0)
                continue

            var peak = PlanMath.segmentPeaks(seg, model.motionProfile)
            if (peak.travel < 1e-6)
                continue

            if (peak.speed > joint.maxSpeedDegPerSec + 1e-6) {
                var minSeconds = PlanMath.segmentMinDuration(model, joint, seg)
                issues.push(issue("error", "stepper-too-fast",
                                  joint.name + ": faster than the axis can move",
                                  "This block needs a peak speed of " + fmt(peak.speed)
                                  + "°/s but " + joint.name + " tops out at "
                                  + fmt(joint.maxSpeedDegPerSec) + "°/s. The motor "
                                  + "would lose steps and every later position on this "
                                  + "axis would be wrong.",
                                  "Give the block at least " + minSeconds.toFixed(2)
                                  + " s, widen the ramp, or raise the axis speed limit "
                                  + "in Robot Model → Axis drives.",
                                  [seg.blockId]))
            }

            if (!isFinite(peak.accel)) {
                issues.push(issue("error", "stepper-instant-start",
                                  joint.name + ": no acceleration ramp",
                                  "A ramp of 0% asks the motor to reach full speed "
                                  + "instantly, which a stepper cannot do from standstill "
                                  + "under load.",
                                  "Drag the ramp out to at least a few percent in the "
                                  + "block inspector.",
                                  [seg.blockId]))
            } else if (peak.accel > joint.maxAccelDegPerSec2 + 1e-6) {
                issues.push(issue("error", "stepper-too-harsh",
                                  joint.name + ": acceleration too harsh",
                                  "The ramp demands " + fmt(peak.accel) + "°/s² but "
                                  + joint.name + " is limited to "
                                  + fmt(joint.maxAccelDegPerSec2) + "°/s².",
                                  "Widen the ramp or lengthen the movement. A longer ramp "
                                  + "spreads the same speed change over more time.",
                                  [seg.blockId]))
            }
        }
    }
}

// -------------------------------------------------------------------------
// Tool below the table
//
// Swept over the whole plan like every other pose rule, and for every kind
// of block: an axis block can put the tool through the table just as well as
// a "move down" can. A WARNING, not an error -- the model only knows the
// bare tool flange and assumes the base stands on the surface below it, and
// an arm on a riser or at the edge of a bench may go lower on purpose.
// -------------------------------------------------------------------------
function checkToolFloor(timeline, model, issues) {
    if (!Kinematics.supports(model) || model.kinematics.floorMm === undefined)
        return

    var floor = model.kinematics.floorMm
    var times = PlanMath.sampleTimes(timeline, SAMPLE_STEP, HOLD_PADDING)
    var jointIds = [model.kinematics.yawJoint].concat(model.kinematics.pitchJoints)
    var pose = {}
    var runs = []
    var run = null

    for (var i = 0; i < times.length; ++i) {
        for (var j = 0; j < jointIds.length; ++j)
            pose[jointIds[j]] = PlanMath.angleAt(timeline, jointIds[j], times[i])
        var depth = floor - Kinematics.forward(model, pose).z

        if (depth > 0.5) {
            if (!run) {
                run = { from: times[i], to: times[i], worstTime: times[i], worstDepth: depth }
                runs.push(run)
            } else {
                run.to = times[i]
                if (depth > run.worstDepth) {
                    run.worstDepth = depth
                    run.worstTime = times[i]
                }
            }
        } else {
            run = null
        }
    }

    for (i = 0; i < runs.length; ++i) {
        var w = runs[i]
        var blockIds = PlanMath.responsibleBlockIds(timeline, jointIds, w.worstTime)
        issues.push(issue("warning", "tool-below-floor",
                          "Tool below the table " + windowText(w),
                          "At " + PlanMath.roundTo(w.worstTime, 2).toFixed(2) + " s the tool "
                          + "flange is " + fmt(w.worstDepth) + " mm below the surface the "
                          + "base stands on" + (blockIds.length === 0
                                                ? " – the start pose itself is that low." : "."),
                          "Shorten the move or raise the arm first. Anything fitted to the "
                          + "flange reaches lower still. If the arm really can go below its "
                          + "base (a riser, the edge of a bench), this can be ignored.",
                          blockIds, w.worstTime))
    }
}

// -------------------------------------------------------------------------
// Two blocks commanding the same servo at the same time
// -------------------------------------------------------------------------
function checkOverlaps(timeline, model, issues) {
    for (var i = 0; i < timeline.overlaps.length; ++i) {
        var o = timeline.overlaps[i]
        var joint = RobotModels.findJoint(model, o.jointId)
        issues.push(issue("error", "same-axis-overlap", joint.name + ": overlapping blocks",
                          "Two blocks drive " + joint.name + " at the same time. One motor can "
                          + "only follow one target at a time.",
                          "Move one block later on the timeline, or shorten the first one. "
                          + "Blocks on DIFFERENT axes may overlap freely – that is how "
                          + "simultaneous movement is expressed. A tool move occupies every "
                          + "axis lane it covers.",
                          o.blockIds))
    }
}

// -------------------------------------------------------------------------
// Angle-difference constraint, sampled across the whole plan
// -------------------------------------------------------------------------

// Values jointB may take while jointA sits at `angleA`, as readable text.
function allowedRangeText(angleA, rule, jointB) {
    var lowLo = angleA - rule.maxDifference
    var lowHi = angleA - rule.minDifference
    var highLo = angleA + rule.minDifference
    var highHi = angleA + rule.maxDifference

    var parts = []
    var lo = Math.max(lowLo, jointB.mechMin)
    var hi = Math.min(lowHi, jointB.mechMax)
    if (hi >= lo)
        parts.push(fmt(lo) + "°–" + fmt(hi) + "°")

    lo = Math.max(highLo, jointB.mechMin)
    hi = Math.min(highHi, jointB.mechMax)
    if (hi >= lo)
        parts.push(fmt(lo) + "°–" + fmt(hi) + "°")

    if (parts.length === 0)
        return "no value inside the mechanical limits of " + jointB.name
    return parts.join(" or ")
}

// Walks the whole plan and groups the moments where `evaluate` reports a
// violation into contiguous time windows, remembering the worst moment in each.
// `evaluate(a, b)` returns 0 when the pose is legal, or how far outside the
// legal region it is.
function scanViolationWindows(timeline, rule, evaluate) {
    var times = PlanMath.sampleTimes(timeline, SAMPLE_STEP, HOLD_PADDING)
    var runs = []
    var run = null

    for (var i = 0; i < times.length; ++i) {
        var t = times[i]
        var a = PlanMath.angleAt(timeline, rule.jointA, t)
        var b = PlanMath.angleAt(timeline, rule.jointB, t)
        var deviation = evaluate(a, b)

        if (deviation > 1e-6) {
            if (!run) {
                run = { from: t, to: t, worstTime: t, worstDeviation: deviation,
                        worstA: a, worstB: b }
                runs.push(run)
            } else {
                run.to = t
                if (deviation > run.worstDeviation) {
                    run.worstDeviation = deviation
                    run.worstTime = t
                    run.worstA = a
                    run.worstB = b
                }
            }
        } else {
            run = null
        }
    }
    return runs
}

function windowText(run) {
    if (Math.abs(run.from - run.to) < 1e-4)
        return "at " + PlanMath.roundTo(run.from, 2).toFixed(2) + " s"
    return "from " + PlanMath.roundTo(run.from, 2).toFixed(2) + " s to "
            + PlanMath.roundTo(run.to, 2).toFixed(2) + " s"
}

// Turns one violation window into a reported issue.
function reportWindow(timeline, rule, run, message, hint, issues) {
    var blockIds = PlanMath.responsibleBlockIds(timeline, [rule.jointA, rule.jointB],
                                                run.worstTime)
    // Nothing has moved yet: the starting pose itself breaks the rule.
    var atStart = run.from < 1e-4 && blockIds.length === 0

    issues.push(issue(
        "error",
        "constraint-" + rule.id,
        rule.title + " violated " + windowText(run),
        message,
        atStart
            ? "The starting pose already breaks this rule. Adjust the start angles in "
              + "Robot Model → Servo channels, or add an opening movement."
            : hint,
        blockIds,
        run.worstTime))
}

function checkAngleDifference(timeline, model, rule, issues) {
    var jointA = RobotModels.findJoint(model, rule.jointA)
    var jointB = RobotModels.findJoint(model, rule.jointB)
    if (!jointA || !jointB)
        return

    var runs = scanViolationWindows(timeline, rule, function (a, b) {
        var diff = Math.abs(a - b)
        if (diff < rule.minDifference)
            return rule.minDifference - diff
        if (diff > rule.maxDifference)
            return diff - rule.maxDifference
        return 0
    })

    for (var r = 0; r < runs.length; ++r) {
        var w = runs[r]
        var diff = Math.abs(w.worstA - w.worstB)
        reportWindow(
            timeline, rule, w,
            jointA.name + " = " + fmt(w.worstA) + "° and " + jointB.name + " = "
                + fmt(w.worstB) + "° give a difference of " + fmt(diff)
                + "°, which is " + (diff < rule.minDifference ? "below" : "above")
                + " the allowed " + fmt(rule.minDifference) + "°–"
                + fmt(rule.maxDifference) + "° band.",
            "At " + PlanMath.roundTo(w.worstTime, 2).toFixed(2) + " s, with " + jointA.name
                + " at " + fmt(w.worstA) + "°, " + jointB.name + " must be within "
                + allowedRangeText(w.worstA, rule, jointB) + ".",
            issues)
    }
}

// jointA must never sit above jointB.
function checkAngleOrder(timeline, model, rule, issues) {
    var jointA = RobotModels.findJoint(model, rule.jointA)
    var jointB = RobotModels.findJoint(model, rule.jointB)
    if (!jointA || !jointB)
        return

    var runs = scanViolationWindows(timeline, rule, function (a, b) {
        return a > b ? a - b : 0
    })

    for (var r = 0; r < runs.length; ++r) {
        var w = runs[r]
        reportWindow(
            timeline, rule, w,
            jointA.name + " = " + fmt(w.worstA) + "° is above " + jointB.name + " = "
                + fmt(w.worstB) + "°, by " + fmt(w.worstA - w.worstB) + "°. "
                + jointA.name + " must stay at or below " + jointB.name + ".",
            "At " + PlanMath.roundTo(w.worstTime, 2).toFixed(2) + " s, either raise "
                + jointB.name + " to at least " + fmt(w.worstA) + "° or lower "
                + jointA.name + " to at most " + fmt(w.worstB) + "°.",
            issues)
    }
}

// -------------------------------------------------------------------------
// Entry point
// -------------------------------------------------------------------------
function validate(blocks, model) {
    var issues = []

    if (!model) {
        return { ok: false, errorCount: 1, warningCount: 0,
                 issues: [issue("error", "no-model", "No robot selected",
                                "Pick a robot model in the sidebar.")],
                 timeline: null, endTime: 0,
                 errorBlockIds: [], warningBlockIds: [] }
    }

    checkBlocks(blocks, model, issues)

    var timeline = PlanMath.build(blocks, model)
    checkMoves(blocks, timeline, model, issues)
    checkOverlaps(timeline, model, issues)
    checkStepperLimits(timeline, model, issues)
    checkToolFloor(timeline, model, issues)

    for (var i = 0; i < model.constraints.length; ++i) {
        var rule = model.constraints[i]
        if (!rule.enabled)
            continue
        if (rule.type === "angleDifference")
            checkAngleDifference(timeline, model, rule, issues)
        else if (rule.type === "angleOrder")
            checkAngleOrder(timeline, model, rule, issues)
    }

    var errorBlockIds = []
    var warningBlockIds = []
    var errors = 0
    var warnings = 0
    for (i = 0; i < issues.length; ++i) {
        var isError = issues[i].severity === "error"
        if (isError)
            errors++
        else
            warnings++
        var bucket = isError ? errorBlockIds : warningBlockIds
        for (var j = 0; j < issues[i].blockIds.length; ++j) {
            if (bucket.indexOf(issues[i].blockIds[j]) === -1)
                bucket.push(issues[i].blockIds[j])
        }
    }

    return {
        ok: errors === 0,
        errorCount: errors,
        warningCount: warnings,
        issues: issues,
        timeline: timeline,
        endTime: timeline.endTime,
        errorBlockIds: errorBlockIds,
        warningBlockIds: warningBlockIds
    }
}
