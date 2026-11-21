// Kinematics.js
//
// Where the tool is for a set of axis angles, and which axis angles put it
// somewhere else. Used by the "move tool" blocks (PlanMath.build) and by the 3D
// view, so the model on screen, the validator and the generated sketch all
// agree on the same geometry.
//
// Pure maths on plain data: no Qt types, no UI.
//
// A robot supports tool moves when its model carries a `kinematics` entry:
//
//   type            "yawPitch3": a base that turns about the vertical, then
//                   three parallel pitch joints in one vertical plane
//                   (shoulder, elbow, wrist). A tool-roll axis after that does
//                   not move the tool point and is ignored here.
//   yawJoint        joint id of the base rotation
//   pitchJoints     [shoulder, elbow, wrist] joint ids
//   shoulderHeightMm  height of the shoulder axis above the table
//   upperArmMm / forearmMm / wristMm   link lengths between the axes; wristMm
//                   runs from the wrist axis to the tool flange
//   toolLengthMm    flange to the tool point, along the tool axis
//   floorMm         optional: height of the surface the base stands on; the
//                   validator warns when the tool point goes below it
//   cad             { jointId: { deg, sign } }: the joint's GEOMETRIC angle is
//                   deg + sign * (rig angle), where the rig angle is what the
//                   3D view turns that joint by (see rigAngle()). `deg` is the
//                   geometric angle in the pose the CAD was built in.
//   moveAccent      colour of the move blocks
//
// Geometric angles
//   yaw             0 = facing the front of the robot, positive = turning left
//                   (counter-clockwise seen from above)
//   shoulder        elevation of the upper arm above the horizontal, 0 = level
//                   and pointing forward, 90 = straight up
//   elbow, wrist    each link's bend relative to the one before it, so the
//                   three ADD UP to the elevation of the tool axis ("pitch")
//
// Robot frame, as seen by the robot itself: X forward, Y left, Z up, origin on
// the table under the base axis. Millimetres.

.pragma library

var DEG = Math.PI / 180.0

// The six tool moves. `axis` is the robot-frame direction of travel.
var DIRECTIONS = [
    { id: "up",      name: "Up",      glyph: "↑", axis: [0, 0, 1]  },
    { id: "down",    name: "Down",    glyph: "↓", axis: [0, 0, -1] },
    { id: "left",    name: "Left",    glyph: "←", axis: [0, 1, 0]  },
    { id: "right",   name: "Right",   glyph: "→", axis: [0, -1, 0] },
    { id: "forward", name: "Forward", glyph: "↗", axis: [1, 0, 0]  },
    { id: "back",    name: "Back",    glyph: "↙", axis: [-1, 0, 0] }
]

function direction(id) {
    for (var i = 0; i < DIRECTIONS.length; ++i) {
        if (DIRECTIONS[i].id === id)
            return DIRECTIONS[i]
    }
    return null
}

function supports(model) {
    return !!model && !!model.kinematics && model.kinematics.type === "yawPitch3"
}

function findJoint(model, jointId) {
    for (var i = 0; i < model.joints.length; ++i) {
        if (model.joints[i].id === jointId)
            return model.joints[i]
    }
    return null
}

// Axes a move in this direction drives, in the model's joint order.
//
// Up and down stay in the arm's own vertical plane: shoulder, elbow and wrist
// (the wrist turns against the other two so the tool keeps its tilt). Every
// horizontal move is a straight line in the ROBOT frame, which in general
// needs the base as well -- a line that does not pass through the base axis
// changes the arm's heading as it goes.
function moveAxes(model, directionId) {
    if (!supports(model))
        return []
    var k = model.kinematics
    var d = direction(directionId)
    var wanted = k.pitchJoints.slice()
    if (d && (d.axis[0] !== 0 || d.axis[1] !== 0))
        wanted.push(k.yawJoint)

    var out = []
    for (var i = 0; i < model.joints.length; ++i) {
        if (wanted.indexOf(model.joints[i].id) !== -1)
            out.push(model.joints[i].id)
    }
    return out
}

// -------------------------------------------------------------------------
// Axis angle <-> rig angle
//
// The rig angle is degrees from the pose the CAD was modelled in. It follows
// the ENCODER, not the program angle: the sketch computes
//   angle = (inverted ? 360 - raw : raw) - encoderOffsetDeg
// so the physical pose for a given program angle moves whenever the offset or
// the inversion changes, and both the 3D view and the tool maths must move
// with it.
// -------------------------------------------------------------------------
function rigAngle(joint, angle) {
    var raw = angle + (joint.encoderOffsetDeg !== undefined ? joint.encoderOffsetDeg : 0)
    if (joint.encoderInverted)
        raw = -raw              // 360 - x, minus a whole turn
    var zero = joint.viewZeroDeg !== undefined ? joint.viewZeroDeg : 0
    return (joint.viewReversed ? -1 : 1) * (raw - zero)
}

function angleFromRig(joint, rig) {
    var zero = joint.viewZeroDeg !== undefined ? joint.viewZeroDeg : 0
    var raw = (joint.viewReversed ? -1 : 1) * rig + zero
    if (joint.encoderInverted)
        raw = -raw
    return raw - (joint.encoderOffsetDeg !== undefined ? joint.encoderOffsetDeg : 0)
}

// The same angle, a whole number of turns away, that lies closest to `near`.
function wrapNear(angle, near) {
    return angle - 360.0 * Math.round((angle - near) / 360.0)
}

function geometricAngle(model, jointId, angle) {
    var c = model.kinematics.cad[jointId]
    return c.deg + c.sign * rigAngle(findJoint(model, jointId), angle)
}

function axisAngle(model, jointId, geometric, near) {
    var c = model.kinematics.cad[jointId]
    var a = angleFromRig(findJoint(model, jointId), (geometric - c.deg) / c.sign)
    return wrapNear(a, near)
}

// -------------------------------------------------------------------------
// Forward kinematics
//
// `pose` is { jointId: axis angle in degrees }. Returns the tool point in the
// robot frame plus the geometric angles it was computed from.
// -------------------------------------------------------------------------
function forward(model, pose) {
    var k = model.kinematics
    var yaw = geometricAngle(model, k.yawJoint, pose[k.yawJoint])
    var g2 = geometricAngle(model, k.pitchJoints[0], pose[k.pitchJoints[0]])
    var g3 = geometricAngle(model, k.pitchJoints[1], pose[k.pitchJoints[1]])
    var g4 = geometricAngle(model, k.pitchJoints[2], pose[k.pitchJoints[2]])

    var a = g2 * DEG
    var b = (g2 + g3) * DEG
    var pitch = g2 + g3 + g4
    var p = pitch * DEG
    var tool = k.wristMm + k.toolLengthMm

    // Signed distance from the base axis, in the arm's own vertical plane.
    // Negative when the arm reaches over its own back.
    var reach = k.upperArmMm * Math.cos(a) + k.forearmMm * Math.cos(b) + tool * Math.cos(p)
    var z = k.shoulderHeightMm
            + k.upperArmMm * Math.sin(a) + k.forearmMm * Math.sin(b) + tool * Math.sin(p)

    return {
        x: reach * Math.cos(yaw * DEG),
        y: reach * Math.sin(yaw * DEG),
        z: z,
        reach: reach,
        yaw: yaw,
        shoulder: g2,
        elbow: g3,
        wrist: g4,
        pitch: pitch
    }
}

// -------------------------------------------------------------------------
// Inverse kinematics
//
// Axis angles that put the tool point at (x, y, z) with the tool axis tilted
// by `pitch`, staying in the same configuration as `pose` (same side of the
// base, elbow bent the same way). Returns
//   { ok: true,  angles: { jointId: degrees } }
//   { ok: false, code, reason, jointId }      why there is no such pose
// -------------------------------------------------------------------------
function inverse(model, x, y, z, pitch, pose) {
    var k = model.kinematics
    var now = forward(model, pose)
    var tool = k.wristMm + k.toolLengthMm
    var p = pitch * DEG

    // Heading. The arm keeps reaching the way it already does: forwards from
    // the base, or over its own back.
    var horizontal = Math.sqrt(x * x + y * y)
    var backwards = now.reach < 0
    var reach = backwards ? -horizontal : horizontal
    var yaw = now.yaw
    if (horizontal > 1e-6) {
        yaw = (backwards ? Math.atan2(-y, -x) : Math.atan2(y, x)) / DEG
        yaw = wrapNear(yaw, now.yaw)
    }

    // Wrist axis: step back from the tool point along the tool axis.
    var wr = reach - tool * Math.cos(p)
    var wz = z - k.shoulderHeightMm - tool * Math.sin(p)
    var l1 = k.upperArmMm
    var l2 = k.forearmMm
    var d2 = wr * wr + wz * wz
    var c3 = (d2 - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)

    if (c3 > 1.0 + 1e-9) {
        return { ok: false, code: "too-far",
                 reason: "the arm is not long enough: the wrist would have to be "
                         + Math.sqrt(d2).toFixed(0) + " mm from the shoulder and the two links "
                         + "only span " + (l1 + l2).toFixed(0) + " mm" }
    }
    if (c3 < -1.0 - 1e-9) {
        return { ok: false, code: "too-close",
                 reason: "the target is too close to the shoulder for the arm to fold onto" }
    }
    c3 = Math.max(-1.0, Math.min(1.0, c3))

    // Keep the elbow bent the way it already is.
    var s3 = Math.sqrt(1.0 - c3 * c3) * (now.elbow < 0 ? -1.0 : 1.0)
    var g3 = Math.atan2(s3, c3) / DEG
    var g2 = (Math.atan2(wz, wr) - Math.atan2(l2 * s3, l1 + l2 * c3)) / DEG
    g2 = wrapNear(g2, now.shoulder)
    g3 = wrapNear(g3, now.elbow)
    var g4 = wrapNear(pitch - g2 - g3, now.wrist)

    var ids = [k.yawJoint, k.pitchJoints[0], k.pitchJoints[1], k.pitchJoints[2]]
    var geo = [yaw, g2, g3, g4]
    var angles = {}
    for (var i = 0; i < ids.length; ++i) {
        var joint = findJoint(model, ids[i])
        var a = axisAngle(model, ids[i], geo[i], pose[ids[i]])
        if (a < joint.mechMin - 1e-6 || a > joint.mechMax + 1e-6) {
            return { ok: false, code: "axis-limit", jointId: ids[i],
                     reason: joint.name + " would have to go to " + a.toFixed(1)
                             + "°, outside its " + joint.mechMin + "°–" + joint.mechMax
                             + "° travel" }
        }
        angles[ids[i]] = a
    }
    return { ok: true, angles: angles }
}

// -------------------------------------------------------------------------
// Joint paths
//
// A straight line of the tool is NOT a straight line of any joint: each axis
// has to follow its own curve for the tool to stay on the line. A tool move
// therefore gives every axis a PATH: its angle at PATH_INTERVALS + 1 evenly
// spaced points along the line, joined by a Catmull-Rom spline so the angle
// and its speed are both continuous.
//
// `u` is how far along the LINE the tool is, 0..1. How u advances in time is
// the block's ordinary motion profile (PlanMath.applyProfile), so the tool
// itself accelerates and brakes along the line on the S-curve.
//
// The generated sketch implements the identical spline (pathAngle /
// pathSlope in ArduinoGeneratorStepper.js). Change one, change the other.
// -------------------------------------------------------------------------
var PATH_INTERVALS = 16
// The line is solved and limit-checked this many times per interval, so a
// line that leaves the workspace between two stored points is still caught.
var PATH_CHECKS = 4

// Cubic through knots i and i+1 of an evenly spaced path, as coefficients of
// ((a*t + b)*t + c)*t + d for t = 0..1. The neighbours beyond either end are
// mirrored, which makes the ends run straight on.
function pathCubic(path, u) {
    var n = path.length - 1
    var x = Math.max(0, Math.min(1, u)) * n
    var i = Math.min(n - 1, Math.floor(x))
    var p1 = path[i]
    var p2 = path[i + 1]
    var p0 = i > 0 ? path[i - 1] : 2.0 * p1 - p2
    var p3 = i + 2 <= n ? path[i + 2] : 2.0 * p2 - p1
    return {
        t: x - i,
        n: n,
        a: -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3,
        b: p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3,
        c: -0.5 * p0 + 0.5 * p2,
        d: p1
    }
}

// Angle at u.
function pathAngle(path, u) {
    var q = pathCubic(path, u)
    return ((q.a * q.t + q.b) * q.t + q.c) * q.t + q.d
}

// d(angle)/du: degrees per whole line.
function pathSlope(path, u) {
    var q = pathCubic(path, u)
    return ((3.0 * q.a * q.t + 2.0 * q.b) * q.t + q.c) * q.n
}

// d2(angle)/du2.
function pathCurvature(path, u) {
    var q = pathCubic(path, u)
    return (6.0 * q.a * q.t + 2.0 * q.b) * q.n * q.n
}

// -------------------------------------------------------------------------
// One tool move: from `pose`, travel `distanceMm` in a STRAIGHT LINE in
// `directionId`, keeping the tool's tilt. Returns
//   ok, code, reason, jointId   as inverse()
//   axes      joint ids the move drives
//   from, to  tool point before and after, { x, y, z }
//   targets   { jointId: degrees } for every axis in `axes`; the pose the move
//             started in when it cannot be solved, so the block still occupies
//             its lanes but commands nothing
//   paths     { jointId: [degrees x (PATH_INTERVALS + 1)] } when ok
//
// The whole line has to be reachable, not just its end: two reachable points
// can have the base, a joint limit or the edge of the reach between them.
// -------------------------------------------------------------------------
function solveMove(model, pose, directionId, distanceMm) {
    var d = direction(directionId)
    var axes = moveAxes(model, directionId)
    var start = forward(model, pose)
    var from = { x: start.x, y: start.y, z: start.z }
    var hold = {}
    var i
    for (i = 0; i < axes.length; ++i)
        hold[axes[i]] = pose[axes[i]]

    function failed(code, reason, to, jointId) {
        return { ok: false, code: code, reason: reason, jointId: jointId,
                 axes: axes, from: from, to: to, targets: hold }
    }

    if (!d)
        return failed("bad-direction", "unknown direction", from)

    var to = { x: start.x + d.axis[0] * distanceMm,
               y: start.y + d.axis[1] * distanceMm,
               z: start.z + d.axis[2] * distanceMm }

    var paths = {}
    for (i = 0; i < axes.length; ++i)
        paths[axes[i]] = [pose[axes[i]]]

    // Walk the line. Each point is solved from the one before it, so the arm
    // keeps its configuration and no angle jumps by a whole turn.
    var current = {}
    for (var id in pose)
        current[id] = pose[id]

    var total = PATH_INTERVALS * PATH_CHECKS
    for (var s = 1; s <= total; ++s) {
        var u = s / total
        var x = start.x + d.axis[0] * distanceMm * u
        var y = start.y + d.axis[1] * distanceMm * u
        var z = start.z + d.axis[2] * distanceMm * u
        var where = s < total ? (distanceMm * u).toFixed(0) + " mm along the line, " : ""

        // Straight over the base axis the heading is undefined, and just
        // beside it the base would have to spin round in an instant.
        if (axes.indexOf(model.kinematics.yawJoint) !== -1
                && Math.sqrt(x * x + y * y) < 10.0) {
            return failed("over-base", where + "the line passes over the base axis, "
                          + "where the base would have to swing round instantly", to)
        }

        var solved = inverse(model, x, y, z, start.pitch, current)
        if (!solved.ok)
            return failed(solved.code, where + solved.reason, to, solved.jointId)

        for (id in solved.angles)
            current[id] = solved.angles[id]
        if (s % PATH_CHECKS === 0) {
            for (i = 0; i < axes.length; ++i)
                paths[axes[i]].push(Math.round(current[axes[i]] * 1000) / 1000)
        }
    }

    var targets = {}
    for (i = 0; i < axes.length; ++i)
        targets[axes[i]] = paths[axes[i]][PATH_INTERVALS]
    return { ok: true, axes: axes, from: from, to: to, targets: targets, paths: paths }
}

// How far the tool is from where it should be on the line, at the worst
// moment of a move: the error left by joining the solved points with a
// spline. Millimetres. (Hundredths of a millimetre in practice -- it is
// reported so that claim can be checked rather than believed.)
function pathDeviation(model, fromPose, paths, from, to) {
    var worst = 0
    var pose = {}
    for (var id in fromPose)
        pose[id] = fromPose[id]

    // Odd multiple, so the samples fall between the stored points, where the
    // spline is furthest from the solved line.
    var total = PATH_INTERVALS * 3
    for (var s = 1; s < total; ++s) {
        var u = s / total
        for (id in paths)
            pose[id] = pathAngle(paths[id], u)
        var p = forward(model, pose)
        var dx = p.x - (from.x + (to.x - from.x) * u)
        var dy = p.y - (from.y + (to.y - from.y) * u)
        var dz = p.z - (from.z + (to.z - from.z) * u)
        worst = Math.max(worst, Math.sqrt(dx * dx + dy * dy + dz * dz))
    }
    return worst
}
