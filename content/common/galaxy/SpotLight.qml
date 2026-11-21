// SpotLight.qml
//
// Light from the cursor on a rectangular surface (Galaxy Theme, spec 6):
//   * edge glow -- the 1 px border lights up near the cursor, a 200 px
//     radial falloff: hsl(268 90% 85% / .95) -> hsl(268 72% 65% / .35) at
//     40 % -> nothing at 70 %
//   * inner light -- a soft 320 px white light, 7 %, under the cursor
// Drop it inside the surface: SpotLight { }. It fills its parent, takes no
// input, and does nothing at all while the cursor is far away.

import QtQuick
import QtQuick.Shapes
import DragonArm

Item {
    id: spot

    property real strength: 1          // the spec's edge-glow knob
    property bool innerLight: true

    anchors.fill: parent
    enabled: false

    // Cursor in this item's coordinates (re-read whenever it moves).
    readonly property point cursor: (AppState.pointerX, AppState.pointerY,
                                     mapFromItem(null, AppState.pointerX, AppState.pointerY))
    readonly property bool near: AppState.pointerInside
                                 && cursor.x > -200 && cursor.y > -200
                                 && cursor.x < width + 200 && cursor.y < height + 200

    Loader {
        anchors.fill: parent
        active: spot.near && spot.width > 0 && spot.height > 0
        sourceComponent: lit
    }

    Component {
        id: lit

        Item {
            id: glow

            readonly property real cx: spot.cursor.x
            readonly property real cy: spot.cursor.y

            // Colour of the edge at distance d from the cursor.
            function edgeAt(d) {
                var t = d / 200
                if (t >= 0.7)
                    return Qt.rgba(0.69, 0.48, 0.92, 0)
                if (t <= 0)
                    return Qt.rgba(0.85, 0.78, 0.98, 0.95 * spot.strength)
                if (t < 0.4) {
                    var k = t / 0.4
                    return Qt.rgba(0.85 + (0.64 - 0.85) * k, 0.78 + (0.42 - 0.78) * k,
                                   0.98 + (0.91 - 0.98) * k, (0.95 + (0.35 - 0.95) * k) * spot.strength)
                }
                var k2 = (t - 0.4) / 0.3
                return Qt.rgba(0.64, 0.42, 0.91, 0.35 * (1 - k2) * spot.strength)
            }

            // Gradient stops along one edge: `along` is the cursor's position
            // projected on the edge, `across` its distance from the edge line.
            function stops(along, across, length) {
                var ks = [-0.7, -0.4, -0.2, 0, 0.2, 0.4, 0.7]
                var out = []
                for (var i = 0; i < ks.length; ++i) {
                    var pos = Math.max(0, Math.min(1, (along + ks[i] * 200) / Math.max(1, length)))
                    var dx = pos * length - along
                    out.push({ p: pos, c: edgeAt(Math.sqrt(dx * dx + across * across)) })
                }
                return out
            }

            readonly property var edgeTop: stops(cx, cy, spot.width)
            readonly property var edgeBottom: stops(cx, spot.height - cy, spot.width)
            readonly property var edgeLeft: stops(cy, cx, spot.height)
            readonly property var edgeRight: stops(cy, spot.width - cx, spot.height)

            anchors.fill: parent

            // ---- inner light (clipped to the surface) ------------------------
            Item {
                anchors.fill: parent
                clip: true
                visible: spot.innerLight

                Shape {
                    x: glow.cx - 320
                    y: glow.cy - 320
                    width: 640
                    height: 640
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: -1
                        fillGradient: RadialGradient {
                            centerX: 320; centerY: 320; centerRadius: 320
                            focalX: 320; focalY: 320
                            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.07) }
                            GradientStop { position: 0.65; color: "transparent" }
                        }
                        PathRectangle { x: 0; y: 0; width: 640; height: 640 }
                    }
                }
            }

            // ---- the four edges ------------------------------------------------
            component Edge: Rectangle {
                id: edge
                property var s: []
                property bool horizontal: true
                gradient: Gradient {
                    orientation: edge.horizontal ? Gradient.Horizontal : Gradient.Vertical
                    GradientStop { position: s.length ? s[0].p : 0; color: s.length ? s[0].c : "transparent" }
                    GradientStop { position: s.length ? s[1].p : 0; color: s.length ? s[1].c : "transparent" }
                    GradientStop { position: s.length ? s[2].p : 0; color: s.length ? s[2].c : "transparent" }
                    GradientStop { position: s.length ? s[3].p : 0; color: s.length ? s[3].c : "transparent" }
                    GradientStop { position: s.length ? s[4].p : 0; color: s.length ? s[4].c : "transparent" }
                    GradientStop { position: s.length ? s[5].p : 0; color: s.length ? s[5].c : "transparent" }
                    GradientStop { position: s.length ? s[6].p : 1; color: s.length ? s[6].c : "transparent" }
                }
            }

            Edge { x: 0; y: 0; width: spot.width; height: 1; horizontal: true; s: glow.edgeTop }
            Edge { x: 0; y: spot.height - 1; width: spot.width; height: 1; horizontal: true; s: glow.edgeBottom }
            Edge { x: 0; y: 0; width: 1; height: spot.height; horizontal: false; s: glow.edgeLeft }
            Edge { x: spot.width - 1; y: 0; width: 1; height: spot.height; horizontal: false; s: glow.edgeRight }
        }
    }
}
