// PoseController.qml
//
// Posing the arm with the mouse, as in animation software. Sits over the 3D
// view and takes only LEFT presses that land on the arm or a handle; the
// camera (CameraController, right / middle button, wheel) is underneath.
//
//   segment (turret, upper arm, forearm, wrist)  drag to turn the axis that
//              segment hangs from -- forward kinematics, one axis block
//   tool       drag to move it in a straight line along the robot's own X,
//              Y or Z (whichever the drag follows) -- one tool-move block
//   arrows     the same, along that one axis
//   ring       round the tool: Axis-5 roll
//
// This item only turns mouse movement into "Axis-3 to 212.5 deg" or "tool
// +37 mm along Z". What that does to the plan -- create a block, refine the
// last one, where on the timeline -- is the session API of `poseTarget`
// (View3DModule): beginPose / updatePose / endPose / cancelPose.
//
// Geometry is read from the rig's own joint nodes, so the handles sit exactly
// on the model that is drawn. Two facts measured on the live scene:
//   * robot frame (X forward, Y left, Z up) is scene (x, z, -y)
//   * a positive rig angle turns a joint right-handed about its scene axis,
//     node.mapDirectionToScene(0, 0, 1)
// The tool point is (0, 0, -10) in the J5 frame -- Kinematics' toolLengthMm.

import QtQuick
import QtQuick3D
import DragonArm

Item {
    id: poser

    property View3D view: null
    property Node orbit: null
    property Camera camera: null
    property var rig: null
    property var pose: []
    property var poseTarget: null
    property bool active: true

    readonly property bool canMoveTool: RobotLibrary.hasKinematics && !!rig
                                        && rig.joints.length >= 5
    readonly property bool dragging: drag !== null

    // What the pointer is over: null, or a hit (see hitTest()).
    property var hover: null
    property var press: null
    property var drag: null
    property real mouseX: 0
    property real mouseY: 0

    readonly property var robotAxes: [Qt.vector3d(1, 0, 0), Qt.vector3d(0, 0, -1),
                                      Qt.vector3d(0, 1, 0)]
    readonly property var axisColors: [Theme.axisX, Theme.axisY, Theme.axisZ]
    readonly property var axisNames: ["forward / back", "left / right", "up / down"]
    readonly property var axisTips: ["fwd", "left", "up"]

    // Esc while dragging.
    function cancel() {
        if (!drag)
            return
        poseTarget.cancelPose()
        drag = null
        press = null
        repaint()
    }

    // Joint accents are strings in the model; Theme.fade() needs a colour.
    function accentOf(joint) {
        return Qt.lighter(joint.accent, 1.0)
    }

    // ---- Geometry ---------------------------------------------------------

    function proj(p) {
        var s = view.mapFrom3DScene(p)
        return Qt.point(s.x, s.y)
    }

    function ray(x, y) {
        var o = view.mapTo3DScene(Qt.vector3d(x, y, 0))
        var f = view.mapTo3DScene(Qt.vector3d(x, y, 1000))
        return { o: o, d: f.minus(o).normalized() }
    }

    function robotToScene(p) {
        return Qt.vector3d(p.x, p.z, -p.y)
    }

    function rotateAbout(p, pivot, axis, deg) {
        var r = p.minus(pivot)
        var th = deg * Math.PI / 180.0
        var c = Math.cos(th), s = Math.sin(th)
        return pivot.plus(r.times(c).plus(axis.crossProduct(r).times(s))
                          .plus(axis.times(axis.dotProduct(r) * (1.0 - c))))
    }

    // Two unit vectors spanning the plane perpendicular to `a`.
    function basis(a) {
        var t = Math.abs(a.y) < 0.9 ? Qt.vector3d(0, 1, 0) : Qt.vector3d(1, 0, 0)
        var u = a.crossProduct(t).normalized()
        return [u, a.crossProduct(u).normalized()]
    }

    // Screen pixels per scene millimetre at `p`.
    function pxPerMm(p) {
        var a = proj(p), b = proj(p.plus(camera.right))
        return Math.max(1e-3, Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)))
    }

    function segmentDistance(px, py, a, b) {
        var vx = b.x - a.x, vy = b.y - a.y
        var len2 = vx * vx + vy * vy
        var u = len2 > 0 ? Math.max(0, Math.min(1, ((px - a.x) * vx + (py - a.y) * vy) / len2)) : 0
        var dx = a.x + u * vx - px, dy = a.y + u * vy - py
        return { d: Math.sqrt(dx * dx + dy * dy), u: u }
    }

    // Parameter along the line p0 + s*d closest to the mouse ray r.
    function closestOnLine(p0, d, r) {
        var w = p0.minus(r.o)
        var b = d.dotProduct(r.d)
        var den = 1.0 - b * b
        if (den < 1e-4)
            return NaN                  // the line points straight at the camera
        return (b * r.d.dotProduct(w) - d.dotProduct(w)) / den
    }

    function jointNode(index) {
        return rig && index < rig.joints.length ? rig.joints[index] : null
    }

    function jointAxis(node) {
        return node.mapDirectionToScene(Qt.vector3d(0, 0, 1)).normalized()
    }

    // Circle of `radiusPx` on screen round `node`'s axis, centred on `centre`
    // (scene). Returns { pts: [screen], scene: [scene] }.
    function axisRing(node, centre, radiusPx, count) {
        var a = jointAxis(node)
        var b = basis(a)
        var r = radiusPx / pxPerMm(centre)
        var pts = [], scene = []
        for (var i = 0; i <= count; ++i) {
            var th = 2 * Math.PI * i / count
            var p = centre.plus(b[0].times(r * Math.cos(th))).plus(b[1].times(r * Math.sin(th)))
            scene.push(p)
            pts.push(proj(p))
        }
        return { pts: pts, scene: scene }
    }

    // The tool handles, in screen space, for the pose on screen right now.
    function toolGizmo() {
        if (!canMoveTool)
            return null
        var tool = rig.joints[4]
        var T = tool.mapPositionToScene(Qt.vector3d(0, 0, -10))
        var t = proj(T)
        var length = 72 / pxPerMm(T)
        var arrows = []
        for (var k = 0; k < 3; ++k) {
            var tip = proj(T.plus(robotAxes[k].times(length)))
            var vx = tip.x - t.x, vy = tip.y - t.y
            arrows.push({ axis: k, from: t, to: tip, vx: vx, vy: vy,
                          visible: Math.sqrt(vx * vx + vy * vy) > 16 })
        }
        return { T: T, t: t, arrows: arrows, ring: axisRing(tool, T, 34, 48) }
    }

    // ---- Hit testing ------------------------------------------------------
    //
    // Returns null (background: orbit) or one of
    //   { kind: "arrow", axis }
    //   { kind: "roll", scene }              Axis-5, grab point on the ring
    //   { kind: "joint", index, scene }      a segment
    //   { kind: "tool", scene }              the last segment
    function hitTest(x, y) {
        if (!rig)
            return null

        var g = toolGizmo()
        if (g) {
            var best = null
            for (var k = 0; k < 3; ++k) {
                var a = g.arrows[k]
                if (!a.visible)
                    continue
                var h = segmentDistance(x, y, a.from, a.to)
                if (h.d < 8 && h.u > 0.18 && (!best || h.d < best.d))
                    best = { kind: "arrow", axis: k, d: h.d }
            }
            for (var i = 1; i < g.ring.pts.length; ++i) {
                var hr = segmentDistance(x, y, g.ring.pts[i - 1], g.ring.pts[i])
                if (hr.d < 6 && (!best || hr.d < best.d))
                    best = { kind: "roll", scene: g.ring.scene[i], d: hr.d }
            }
            if (best)
                return best
        }

        var r = view.pick(x, y)
        if (!r.objectHit)
            return null
        var link = rig.linkOf(r.objectHit)
        if (link.length < 2 || link.charAt(0) !== "j")
            return null                      // the base: orbit
        var index = parseInt(link.substring(1)) - 1
        if (index >= RobotLibrary.joints.length)
            return null
        if (index === 4 && canMoveTool)
            return { kind: "tool", scene: r.scenePosition }
        return { kind: "joint", index: index, scene: r.scenePosition }
    }

    // ---- Dragging ---------------------------------------------------------

    function beginJointDrag(hit, x, y, together) {
        var node = jointNode(hit.index)
        var joint = RobotLibrary.joints[hit.index]
        if (!node || !joint)
            return null

        // Where on the segment it was grabbed, in the joint's own frame, so it
        // follows the segment as it turns. A point right on the axis has no
        // leverage; seen edge-on, leverage only comes from moving towards the
        // camera. Either way, put the grab point where a drag turns it best.
        var pivot = node.scenePosition
        var a = jointAxis(node)
        var view_ = ray(x, y).d
        var rel = hit.scene.minus(pivot)
        var along = a.dotProduct(rel)
        var radial = rel.minus(a.times(along))
        var reach = Math.max(40, radial.length())
        var dir = radial.length() > 1e-3 ? radial.normalized() : basis(a)[0]
        if (Math.abs(a.dotProduct(view_)) < 0.5) {
            var towards = view_.times(-1)
            var flat = towards.minus(a.times(a.dotProduct(towards)))
            if (flat.length() > 1e-3)
                dir = flat.normalized()
        }
        var grab = pivot.plus(a.times(along)).plus(dir.times(reach))
        var grabLocal = node.mapPositionFromScene(grab)

        poseTarget.beginPose("axis", joint.id, together)
        var angle = hit.index < poser.pose.length ? poser.pose[hit.index] : joint.homeAngle

        // Two ways to turn a drag into an angle:
        //   plane    -- where the mouse ray meets the plane the grab point
        //               turns in. Exact: the grabbed point stays under the
        //               cursor. Used whenever that plane is reasonably open
        //               to the camera.
        //   slide    -- seen edge-on the plane is a line and the ray meets it
        //               anywhere; then the drag along the grab point's screen
        //               motion is what counts.
        var d = {
            kind: "joint",
            index: hit.index,
            jointId: joint.id,
            grabLocal: grabLocal,
            // The exact point that was clicked, for checking that it follows
            // the cursor (plane mode keeps it under it).
            pickLocal: node.mapPositionFromScene(hit.scene),
            rig: RobotLibrary.rigAngle(joint.id, angle),
            lastX: x,
            lastY: y,
            plane: Math.abs(a.dotProduct(view_)) >= 0.3
        }
        if (d.plane) {
            // The plane is fixed for the whole drag: only this joint turns,
            // and nothing it carries moves its own axis.
            d.pivot = pivot
            d.axis = a
            d.centre = pivot.plus(a.times(along))
            d.basis = basis(a)
            d.rig0 = d.rig
            d.lastAngle = planeAngle(d, x, y)
            d.turned = 0
            if (isNaN(d.lastAngle))
                d.plane = false
        }
        return d
    }

    // Angle (deg) round the joint axis of the point where the mouse ray meets
    // the joint's turning plane; NaN when it does not meet it in front.
    function planeAngle(d, x, y) {
        var r = ray(x, y)
        var den = r.d.dotProduct(d.axis)
        if (Math.abs(den) < 1e-6)
            return NaN
        var s = d.centre.minus(r.o).dotProduct(d.axis) / den
        if (s <= 0)
            return NaN
        var rel = r.o.plus(r.d.times(s)).minus(d.centre)
        return Math.atan2(rel.dotProduct(d.basis[1]), rel.dotProduct(d.basis[0])) * 180.0 / Math.PI
    }

    function beginToolDrag(axis, pressX, pressY) {
        var started = poseTarget.beginPose("tool", axis, false)
        if (!started || !started.origin)
            return null
        var p0 = robotToScene(started.origin)
        var d = robotAxes[axis]
        var s0 = closestOnLine(p0, d, ray(pressX, pressY))
        if (isNaN(s0)) {
            poseTarget.cancelPose()
            return null
        }
        return { kind: "tool", axis: axis, p0: p0, d: d, s0: s0 }
    }

    // The axis a free drag of the tool follows: the one whose arrow points
    // most nearly the way the mouse moved.
    function inferAxis(dx, dy) {
        var g = toolGizmo()
        var best = -1, bestScore = 0
        var len = Math.sqrt(dx * dx + dy * dy)
        for (var k = 0; g && k < 3; ++k) {
            var a = g.arrows[k]
            if (!a.visible)
                continue
            var score = Math.abs(dx * a.vx + dy * a.vy) / (len * Math.sqrt(a.vx * a.vx + a.vy * a.vy))
            if (score > bestScore) {
                bestScore = score
                best = k
            }
        }
        return best
    }

    function startDrag(x, y) {
        var hit = press ? press.hit : null
        if (!hit)
            return
        var together = (press.modifiers & Qt.ShiftModifier) !== 0
        if (hit.kind === "joint")
            drag = beginJointDrag(hit, press.x, press.y, together)
        else if (hit.kind === "roll")
            drag = beginJointDrag({ kind: "joint", index: 4, scene: hit.scene },
                                  press.x, press.y, together)
        else if (hit.kind === "arrow")
            drag = beginToolDrag(hit.axis, press.x, press.y)
        else if (hit.kind === "tool") {
            var axis = inferAxis(x - press.x, y - press.y)
            drag = axis < 0 ? null : beginToolDrag(axis, press.x, press.y)
        }
        if (drag)
            continueDrag(x, y)
    }

    function continueDrag(x, y) {
        var d = drag
        if (d.kind === "joint") {
            if (d.plane) {
                var now = planeAngle(d, x, y)
                if (isNaN(now))
                    return
                // Unwrapped, so circling the pivot more than once keeps going.
                var delta = now - d.lastAngle
                delta -= 360.0 * Math.round(delta / 360.0)
                d.lastAngle = now
                d.turned += delta
                d.rig = d.rig0 + d.turned
            } else {
                // Edge-on: how many screen pixels one degree moves the grab
                // point right now, and how far the mouse went along that.
                var node = jointNode(d.index)
                var pivot = node.scenePosition
                var a = jointAxis(node)
                var p = node.mapPositionToScene(d.grabLocal)
                var s0 = proj(p), s1 = proj(rotateAbout(p, pivot, a, 1.0))
                var jx = s1.x - s0.x, jy = s1.y - s0.y
                var jj = jx * jx + jy * jy
                var mx = x - d.lastX, my = y - d.lastY
                d.lastX = x
                d.lastY = y
                if (jj < 0.04)
                    return                   // no leverage from here
                var step = (mx * jx + my * jy) / jj
                d.rig += Math.max(-12, Math.min(12, step))
            }

            var joint = RobotLibrary.joints[d.index]
            var angle = RobotLibrary.angleFromRig(d.jointId, d.rig)
            var clamped = Math.max(joint.nominalMin, Math.min(joint.nominalMax, angle))
            if (clamped !== angle && !d.plane)
                d.rig = RobotLibrary.rigAngle(d.jointId, clamped)
            // (In plane mode the mouse keeps its own angle past a limit, so
            // coming back starts turning again exactly where the limit is.)
            poseTarget.updatePose(clamped)
        } else {
            var s = closestOnLine(d.p0, d.d, ray(x, y))
            if (!isNaN(s))
                poseTarget.updatePose(s - d.s0)
        }
        repaint()
    }

    // ---- Drawing ----------------------------------------------------------

    function repaint() {
        overlay.requestPaint()
    }

    onPoseChanged: repaint()
    onActiveChanged: repaint()
    onRigChanged: repaint()
    onWidthChanged: repaint()
    onHeightChanged: repaint()

    Connections {
        target: poser.orbit
        function onEulerRotationChanged() { poser.repaint() }
        function onPositionChanged() { poser.repaint() }
    }
    Connections {
        target: poser.camera
        function onPositionChanged() { poser.repaint() }
        function onZChanged() { poser.repaint() }
    }

    Canvas {
        id: overlay
        anchors.fill: parent
        visible: poser.active && !!poser.rig

        function polyline(ctx, pts) {
            ctx.beginPath()
            for (var i = 0; i < pts.length; ++i) {
                if (i === 0)
                    ctx.moveTo(pts[i].x, pts[i].y)
                else
                    ctx.lineTo(pts[i].x, pts[i].y)
            }
            ctx.stroke()
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (!poser.active || !poser.rig || !poser.view)
                return
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            var hover = poser.hover
            var drag = poser.drag

            // -- the ring of the joint being turned, or about to be --------
            var ringIndex = drag && drag.kind === "joint" ? drag.index
                          : (!drag && hover && hover.kind === "joint" ? hover.index : -1)
            if (ringIndex >= 0 && ringIndex < 4) {
                var node = poser.jointNode(ringIndex)
                var joint = RobotLibrary.joints[ringIndex]
                var ring = poser.axisRing(node, node.scenePosition, 64, 64)
                ctx.strokeStyle = Theme.fade(poser.accentOf(joint), drag ? 0.95 : 0.7)
                ctx.lineWidth = drag ? 3 : 2
                polyline(ctx, ring.pts)
                if (drag) {
                    var c = poser.proj(node.scenePosition)
                    var g = poser.proj(node.mapPositionToScene(drag.grabLocal))
                    ctx.lineWidth = 1.5
                    polyline(ctx, [c, g])
                    ctx.fillStyle = poser.accentOf(joint)
                    ctx.beginPath()
                    ctx.arc(g.x, g.y, 4, 0, 2 * Math.PI)
                    ctx.fill()
                }
            }

            // -- tool handles ----------------------------------------------
            var gz = poser.toolGizmo()
            if (!gz)
                return

            if (drag && drag.kind === "tool") {
                // Guide: the straight line the tool is being moved along.
                var a0 = poser.proj(drag.p0.plus(drag.d.times(-600)))
                var a1 = poser.proj(drag.p0.plus(drag.d.times(600)))
                ctx.strokeStyle = Theme.fade(poser.axisColors[drag.axis], 0.6)
                ctx.lineWidth = 1.5
                ctx.setLineDash([6, 5])
                polyline(ctx, [a0, a1])
                ctx.setLineDash([])
                var o = poser.proj(drag.p0)
                ctx.fillStyle = Theme.textSecondary
                ctx.beginPath()
                ctx.arc(o.x, o.y, 3.5, 0, 2 * Math.PI)
                ctx.fill()
            }

            var rollJoint = RobotLibrary.joints.length > 4 ? RobotLibrary.joints[4] : null
            var rollHot = (hover && hover.kind === "roll" && !drag)
                          || (drag && drag.kind === "joint" && drag.index === 4)
            if (rollJoint) {
                ctx.strokeStyle = Theme.fade(poser.accentOf(rollJoint), rollHot ? 1.0 : 0.55)
                ctx.lineWidth = rollHot ? 3 : 1.6
                polyline(ctx, gz.ring.pts)
            }

            ctx.font = 'bold 10px "Segoe UI"'
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            for (var k = 0; k < 3; ++k) {
                var ar = gz.arrows[k]
                if (!ar.visible)
                    continue
                var hot = (hover && !drag && (hover.kind === "arrow" && hover.axis === k))
                          || (drag && drag.kind === "tool" && drag.axis === k)
                var col = poser.axisColors[k]
                var len = Math.sqrt(ar.vx * ar.vx + ar.vy * ar.vy)
                var ux = ar.vx / len, uy = ar.vy / len
                ctx.strokeStyle = Theme.fade(col, hot ? 1.0 : 0.8)
                ctx.fillStyle = ctx.strokeStyle
                ctx.lineWidth = hot ? 3.2 : 2
                polyline(ctx, [Qt.point(ar.from.x + ux * 8, ar.from.y + uy * 8), ar.to])
                // arrow head
                var hs = hot ? 10 : 8
                ctx.beginPath()
                ctx.moveTo(ar.to.x + ux * hs, ar.to.y + uy * hs)
                ctx.lineTo(ar.to.x - uy * hs * 0.5, ar.to.y + ux * hs * 0.5)
                ctx.lineTo(ar.to.x + uy * hs * 0.5, ar.to.y - ux * hs * 0.5)
                ctx.closePath()
                ctx.fill()
                ctx.fillText(poser.axisTips[k], ar.to.x + ux * (hs + 14),
                             ar.to.y + uy * (hs + 14))
            }

            // tool point
            ctx.fillStyle = Theme.textPrimary
            ctx.beginPath()
            ctx.arc(gz.t.x, gz.t.y, 3, 0, 2 * Math.PI)
            ctx.fill()
        }
    }

    // ---- What a drag does, next to the cursor -----------------------------
    readonly property string hintText: {
        if (drag)
            return poseTarget ? poseTarget.poseStatus : ""
        var h = hover
        if (!h)
            return ""
        if (h.kind === "joint")
            return RobotLibrary.joints[h.index].name + " · drag to turn"
                    + " · Shift: with the last step"
        if (h.kind === "roll")
            return (RobotLibrary.joints.length > 4 ? RobotLibrary.joints[4].name : "Roll")
                    + " · drag round the ring"
        if (h.kind === "arrow")
            return "Move tool " + axisNames[h.axis] + " · straight line"
        if (h.kind === "tool")
            return "Move tool · drag along forward, left or up"
        return ""
    }
    readonly property string noteText: drag && poseTarget ? poseTarget.poseNote : ""

    Rectangle {
        visible: poser.active && (label.text.length > 0 || note.text.length > 0)
        x: Math.min(poser.width - width - 4, poser.mouseX + 16)
        y: Math.max(4, poser.mouseY - height - 10)
        width: Math.max(label.implicitWidth, note.visible ? Math.min(note.implicitWidth, 320) : 0) + 16
        height: column.implicitHeight + 10
        radius: Theme.radiusSmall
        color: Theme.fade(Theme.surfaceSolid, 0.94)
        border.width: 1
        border.color: note.visible ? Theme.danger : Theme.border

        Column {
            id: column
            anchors.centerIn: parent
            spacing: 2

            Text {
                id: label
                text: poser.hintText
                visible: text.length > 0
                color: Theme.textPrimary
                font.family: poser.drag ? Theme.monoFamily : Theme.fontFamily
                font.pixelSize: Theme.fontSmall
                font.bold: !!poser.drag
            }

            Text {
                id: note
                width: Math.min(implicitWidth, 320)
                text: poser.noteText
                visible: text.length > 0
                wrapMode: Text.WordWrap
                color: Theme.danger
                font.family: Theme.fontFamily
                font.weight: Theme.weightBody
                font.pixelSize: Theme.fontTiny
            }
        }
    }

    // ---- Input ------------------------------------------------------------
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: poser.active && !!poser.rig && !!poser.poseTarget
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: poser.drag ? Qt.ClosedHandCursor
                                : (poser.hover ? (poser.hover.kind === "arrow"
                                                  ? Qt.SizeAllCursor : Qt.OpenHandCursor)
                                               : Qt.ArrowCursor)

        property bool hoverPending: false

        function refreshHover() {
            hoverPending = false
            if (poser.drag || pressed)
                return
            poser.hover = poser.hitTest(poser.mouseX, poser.mouseY)
            poser.repaint()
        }

        onPositionChanged: function (m) {
            poser.mouseX = m.x
            poser.mouseY = m.y
            if (!pressed) {
                // Picking is cheap, but not worth doing more than once a frame.
                if (!hoverPending) {
                    hoverPending = true
                    Qt.callLater(refreshHover)
                }
                return
            }
            if (!poser.press)
                return
            if (!poser.drag) {
                if (Math.abs(m.x - poser.press.x) < 4 && Math.abs(m.y - poser.press.y) < 4)
                    return
                poser.startDrag(m.x, m.y)
                return
            }
            poser.continueDrag(m.x, m.y)
        }

        onPressed: function (m) {
            var hit = poser.hitTest(m.x, m.y)
            if (!hit) {
                m.accepted = false           // background: the camera's (it orbits
                                             // with the left button only while
                                             // posing is off)
                return
            }
            poser.press = { x: m.x, y: m.y, hit: hit, modifiers: m.modifiers }
            poser.hover = hit
        }

        onReleased: {
            if (poser.drag)
                poser.poseTarget.endPose()
            poser.drag = null
            poser.press = null
            refreshHover()
        }

        onCanceled: poser.cancel()

        // The wheel is the camera's: zoom passes straight through.
        onWheel: function (w) { w.accepted = false }

        onExited: {
            if (!pressed) {
                poser.hover = null
                poser.repaint()
            }
        }
    }
}
