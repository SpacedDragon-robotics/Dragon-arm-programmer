// GalaxyBackground.qml
//
// The space scene behind the whole app (Galaxy Theme, spec section 6):
//   * a grey Milky-Way band with thin dark dust lanes, bottom-left to
//     top-right, plus scattered stars -- painted ONCE per window size into a
//     Canvas, with a seeded random generator so it never reshuffles
//   * twinkling stars and slowly rising out-of-focus dust (particles, GPU)
//   * a vignette darkening the edges
//   * a small soft light under the cursor
// Everything shifts a little against the cursor (parallax).
//
// It takes no input and sits under all content.

import QtQuick
import QtQuick.Particles
import QtQuick.Shapes
import DragonArm

Item {
    id: bg

    // Window-coordinate pointer, smoothed (the spec eases at 4/s) so the
    // parallax glides instead of jittering.
    property real smx: width / 2
    property real smy: height * 0.4
    readonly property real px: width > 0 ? (smx - width / 2) / width : 0
    readonly property real py: height > 0 ? (smy - height / 2) / height : 0

    FrameAnimation {
        running: bg.visible && AppState.pointerInside
                 && (Math.abs(AppState.pointerX - bg.smx) > 0.5
                     || Math.abs(AppState.pointerY - bg.smy) > 0.5)
        onTriggered: {
            var f = Math.min(1, frameTime * 4)
            bg.smx += (AppState.pointerX - bg.smx) * f
            bg.smy += (AppState.pointerY - bg.smy) * f
        }
    }

    // ---- Base: bg colour + two soft radial glows (grey top-left, purple
    //      bottom-right) -------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Theme.backgroundDeep
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: bg.width * 0.10; centerY: -bg.height * 0.12
                centerRadius: 1200 * 0.62
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: Qt.rgba(0.335, 0.33, 0.345, 0.38) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: bg.width; height: bg.height }
        }
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: bg.width * 1.05; centerY: bg.height * 1.12
                centerRadius: 900 * 0.62
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: Qt.rgba(0.26, 0.08, 0.48, 0.09) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: bg.width; height: bg.height }
        }
    }

    // ---- Nebula band + static stars (painted once per size) ----------------
    Canvas {
        id: sky

        // Half resolution, drawn at double size: it is all soft haze.
        x: -30 - bg.px * 18
        y: -30 - bg.py * 18
        width: Math.ceil((bg.width + 60) / 2)
        height: Math.ceil((bg.height + 60) / 2)
        scale: 2
        transformOrigin: Item.TopLeft
        opacity: 0.6                       // spec: nebula 0.6
        renderStrategy: Canvas.Cooperative

        onWidthChanged: repaintLater.restart()
        onHeightChanged: repaintLater.restart()

        Timer {
            id: repaintLater
            interval: 150
            onTriggered: sky.requestPaint()
        }

        // mulberry32, like the spec's engine: same seed, same sky.
        function prng(seed) {
            return function () {
                seed |= 0; seed = (seed + 0x6D2B79F5) | 0
                var t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
                t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296
            }
        }
        function gauss(r) {
            var u = 0, v = 0
            while (!u) u = r()
            while (!v) v = r()
            return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v)
        }

        onPaint: {
            var g = getContext("2d")
            var W = width, H = height, M = Math.max(W, H)
            g.reset()
            if (W < 2 || H < 2)
                return
            var r = prng(7 * 31 + 1)

            function blob(x, y, rad, rgb, a) {
                var gr = g.createRadialGradient(x, y, 0, x, y, rad)
                gr.addColorStop(0, "rgba(" + rgb + "," + a + ")")
                gr.addColorStop(1, "rgba(" + rgb + ",0)")
                g.fillStyle = gr
                g.fillRect(x - rad, y - rad, rad * 2, rad * 2)
            }
            // A point on the diagonal band: (-10%, 95%) -> (110%, 10%).
            function band(spread, shift) {
                var t = r(), off = gauss(r) * spread + (shift || 0)
                return [(-0.1 + 1.2 * t + off * 0.58) * W, (0.95 - 0.85 * t + off * 0.82) * H, t]
            }

            // hsl(268 8% 72%), hsl(268 72% 52%), hsl(268 72% 32%)
            var gray = "186,180,189", purple = "130,59,226", deep = "79,23,140"
            var i, p
            g.globalCompositeOperation = "lighter"
            for (i = 0; i < 170; ++i) { p = band(0.07); blob(p[0], p[1], (0.04 + r() * 0.13) * M, gray, 0.05) }
            for (i = 0; i < 40; ++i) { p = band(0.16); blob(p[0], p[1], (0.06 + r() * 0.18) * M, purple, 0.028) }
            for (i = 0; i < 5; ++i) blob(r() * W, r() * H, (0.15 + r() * 0.25) * M, deep, 0.045)
            g.globalCompositeOperation = "source-over"

            // dense dust stars along the band, brightest in its middle
            var n = Math.round(W * H / 90)
            for (i = 0; i < n; ++i) {
                p = band(0.05)
                var core = Math.exp(-Math.pow((p[2] - 0.5) / 0.12, 2))
                g.fillStyle = "rgba(255,255,255," + ((0.08 + r() * 0.3) * (0.5 + core)) + ")"
                g.fillRect(p[0], p[1], 0.6, 0.6)
            }

            // dark dust lanes, slightly off the band's centre line
            g.globalCompositeOperation = "destination-out"
            for (i = 0; i < 90; ++i) { p = band(0.02, 0.025); blob(p[0], p[1], (0.01 + r() * 0.03) * M, "0,0,0", 0.3) }
            g.globalCompositeOperation = "source-over"
        }
    }

    // Steady stars at full resolution: half scattered, half in the band.
    Canvas {
        id: stars

        x: -12 - bg.px * 15
        y: -12 - bg.py * 15
        width: bg.width + 24
        height: bg.height + 24
        renderStrategy: Canvas.Cooperative

        onWidthChanged: starsLater.restart()
        onHeightChanged: starsLater.restart()

        Timer {
            id: starsLater
            interval: 150
            onTriggered: stars.requestPaint()
        }

        onPaint: {
            var g = getContext("2d")
            var W = width, H = height
            g.reset()
            if (W < 2 || H < 2)
                return
            var r = sky.prng(7)
            // The twinkling ones are particles (below); these are the rest.
            var n = Math.round(W * H / 2200 * 0.75)
            var cols = ["255,255,255", "214,192,247", "255,224,192"]   // white, lavender, pale warm
            for (var i = 0; i < n; ++i) {
                var x, y
                if (r() < 0.5) {
                    var t = r(), off = sky.gauss(r) * 0.1
                    x = (-0.1 + 1.2 * t + off * 0.58) * W
                    y = (0.95 - 0.85 * t + off * 0.82) * H
                } else {
                    x = r() * W
                    y = r() * H
                }
                var z = r(), big = r() < 0.035, cr = r()
                var rad = big ? 0.9 + r() * 0.9 : (0.25 + r() * 0.6) * (0.6 + z * 0.6)
                var a = 0.25 + r() * 0.7
                var c = cols[cr < 0.78 ? 0 : (cr < 0.93 ? 1 : 2)]
                if (big) {
                    var gr = g.createRadialGradient(x, y, 0, x, y, rad * 7)
                    gr.addColorStop(0, "rgba(255,255,255," + (a * 0.35) + ")")
                    gr.addColorStop(1, "rgba(255,255,255,0)")
                    g.fillStyle = gr
                    g.fillRect(x - rad * 7, y - rad * 7, rad * 14, rad * 14)
                }
                g.fillStyle = "rgba(" + c + "," + a + ")"
                g.fillRect(x, y, Math.max(0.5, rad * 1.6), Math.max(0.5, rad * 1.6))
            }
        }
    }

    // ---- Twinkling stars and rising dust (particles) ------------------------
    ParticleSystem {
        id: skyParticles
        x: -bg.px * 20
        y: -bg.py * 20
        width: bg.width
        height: bg.height
        running: bg.visible
    }

    // Twinkle: stars that fade in and out where they are.
    ImageParticle {
        system: skyParticles
        groups: ["twinkle"]
        source: "qrc:///particleresources/glowdot.png"
        color: Theme.starColor
        colorVariation: 0.06
        alpha: 0.75
        alphaVariation: 0.35
        entryEffect: ImageParticle.Fade
    }
    Emitter {
        system: skyParticles
        group: "twinkle"
        anchors.fill: parent
        emitRate: Math.round(bg.width * bg.height / 2200 * 0.25 / 2.6)
        lifeSpan: 2600
        lifeSpanVariation: 1400
        // The glow sprite is mostly halo: 3 px reads as a ~1 px star.
        size: 3
        sizeVariation: 1
        startTime: 3000
    }

    // Bokeh: a few soft out-of-focus discs drifting upward.
    ImageParticle {
        system: skyParticles
        groups: ["bokeh"]
        source: "qrc:///particleresources/fuzzydot.png"
        // Purple-grey and faint (spec: 8-30 %). The painter's own `alpha`
        // and a translucent `color` both turned out not to dim the bright
        // fuzzydot sprite; opacity on the painter item does, reliably.
        color: Theme.bokehColor
        colorVariation: 0.06
        opacity: 0.22
        entryEffect: ImageParticle.Fade
    }
    Emitter {
        system: skyParticles
        group: "bokeh"
        anchors.fill: parent
        emitRate: 8 / 22
        lifeSpan: 22000
        lifeSpanVariation: 6000
        size: 24
        sizeVariation: 16
        startTime: 30000
        velocity: AngleDirection { angle: 270; angleVariation: 25; magnitude: 4; magnitudeVariation: 2 }
    }

    // ---- Vignette ---------------------------------------------------------------
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: bg.width * 0.5; centerY: bg.height * 0.45
                centerRadius: Math.max(bg.width * 0.6, bg.height * 0.45) * 1.0
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.55; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
            }
            PathRectangle { x: 0; y: 0; width: bg.width; height: bg.height }
        }
    }

    // ---- Cursor light ------------------------------------------------------------
    // Purple-white light across 50 px, with a white core a fifth that size.
    Shape {
        id: cursorLight
        readonly property real r: Theme.cursorRadius
        x: AppState.pointerX - r
        y: AppState.pointerY - r
        width: r * 2
        height: r * 2
        opacity: AppState.pointerInside ? 1 : 0
        preferredRendererType: Shape.CurveRenderer

        Behavior on opacity {
            NumberAnimation { duration: 600; easing.type: Theme.easing }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: cursorLight.r; centerY: cursorLight.r
                centerRadius: cursorLight.r
                focalX: centerX; focalY: centerY
                // hsl(268 55% 72% / .14), fading out by 62 %
                GradientStop { position: 0; color: Qt.rgba(0.72, 0.6, 0.87, Theme.cursorLight) }
                GradientStop { position: 0.62; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: cursorLight.width; height: cursorLight.height }
        }
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: cursorLight.r; centerY: cursorLight.r
                centerRadius: cursorLight.r * 0.22
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, Theme.cursorLight * 0.5) }
                GradientStop { position: 0.7; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: cursorLight.width; height: cursorLight.height }
        }
    }
}
