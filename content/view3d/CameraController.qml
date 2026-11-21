// CameraController.qml
//
// Orbit / pan / zoom for the 3D view, on buttons that leave the LEFT button to
// the posing (PoseController):
//
//   right-drag              orbit round the target
//   middle-drag, Shift+right-drag   pan
//   wheel                   zoom
//   left-drag               orbit too, but only while posing is switched off
//
// Our own rather than QtQuick3D.Helpers' OrbitCameraController: that one
// orbits on the left button, and only Qt 6.9+ lets the button be changed --
// Design Studio runs Qt 6.8. It is also a plain MouseArea, so real mouse
// events in qmltestrunner reach it (the Helpers' DragHandler never activated
// there).
//
// The camera is a child of `origin` at (0, 0, distance): orbiting turns the
// origin, panning moves it, zooming changes the camera's z.

import QtQuick
import QtQuick3D

MouseArea {
    id: controller

    required property Node origin
    required property Camera camera
    // Left-drag orbits as well (posing is off, so the left button is free).
    property bool leftOrbits: false

    property real degreesPerPixel: 0.35
    property real minDistance: 150
    property real maxDistance: 6000
    property real minPitch: -89
    property real maxPitch: 89

    acceptedButtons: leftOrbits ? (Qt.LeftButton | Qt.RightButton | Qt.MiddleButton)
                                : (Qt.RightButton | Qt.MiddleButton)

    property point last
    property bool panning: false

    cursorShape: pressed ? (panning ? Qt.SizeAllCursor : Qt.ClosedHandCursor) : Qt.ArrowCursor

    onPressed: function (m) {
        last = Qt.point(m.x, m.y)
        panning = m.button === Qt.MiddleButton
                  || (m.button === Qt.RightButton && (m.modifiers & Qt.ShiftModifier))
    }

    onPositionChanged: function (m) {
        var dx = m.x - last.x
        var dy = m.y - last.y
        last = Qt.point(m.x, m.y)

        if (panning) {
            // Move the target so the scene follows the mouse: one pixel is
            // the size of a pixel at the target's distance.
            var mmPerPx = 2.0 * camera.z * Math.tan(camera.fieldOfView * Math.PI / 360.0)
                          / Math.max(1, height)
            origin.position = origin.position
                    .minus(origin.right.times(dx * mmPerPx))
                    .plus(origin.up.times(dy * mmPerPx))
            return
        }

        // Drag right: the model turns right. Drag down: look from higher up.
        var r = origin.eulerRotation
        var pitch = Math.max(minPitch, Math.min(maxPitch, r.x - dy * degreesPerPixel))
        origin.eulerRotation = Qt.vector3d(pitch, r.y - dx * degreesPerPixel, 0)
    }

    onReleased: panning = false

    onWheel: function (w) {
        // ~12 % per notch, towards the target.
        var z = camera.z * Math.pow(0.88, w.angleDelta.y / 120.0)
        camera.z = Math.max(minDistance, Math.min(maxDistance, z))
    }
}
