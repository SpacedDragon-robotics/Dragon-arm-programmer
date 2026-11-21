// GlowShadow.qml
//
// A soft shadow (or glow) cast by its parent, drawn only OUTSIDE the
// parent's rectangle -- like a CSS box-shadow, which never shows through
// the box itself. That matters here: the surfaces are glass, and a shadow
// drawn underneath would darken what should be seen through them.
//
// Two uses (Galaxy Theme, spec section 6):
//   * the cursor shadow: black, falling AWAY from the cursor
//         GlowShadow { followCursor: true }
//   * the purple under-glow of hovered items
//         GlowShadow { colour: Theme.accentGlow; offsetY: 18; blur: 36; spread: -10 }
//
// Built from proven parts: a blurred caster rectangle (MultiEffect shadow)
// with the parent's own rectangle cut out of it by an inverted mask.

import QtQuick
import QtQuick.Effects
import DragonArm

Item {
    id: glow

    property color colour: Qt.rgba(0, 0, 0, Theme.shadowAlpha)
    property real offsetX: 0
    property real offsetY: 12
    property real blur: 44              // px, like the CSS blur radius
    property real spread: -10           // px; negative shrinks the caster
    // Cursor shadow: add an offset pointing away from the cursor, up to
    // Theme.shadowDistance px, growing with the distance (spec: d / 420).
    property bool followCursor: false

    readonly property real pad: blur + Theme.shadowDistance + Math.abs(offsetY) + 8

    readonly property point away: {
        if (!followCursor || !AppState.pointerInside || !parent)
            return Qt.point(0, 0)
        var c = parent.mapToItem(null, parent.width / 2, parent.height / 2)
        var dx = c.x - AppState.pointerX, dy = c.y - AppState.pointerY
        var d = Math.sqrt(dx * dx + dy * dy) || 1
        var k = Math.min(d / 420, 1) * Theme.shadowDistance
        return Qt.point(dx / d * k, dy / d * k)
    }

    anchors.fill: parent
    z: -1
    enabled: false

    Item {
        id: caster
        visible: false
        x: -glow.pad
        y: -glow.pad
        width: glow.width + 2 * glow.pad
        height: glow.height + 2 * glow.pad

        Rectangle {
            x: glow.pad - glow.spread
            y: glow.pad - glow.spread
            width: Math.max(0, glow.width + 2 * glow.spread)
            height: Math.max(0, glow.height + 2 * glow.spread)
            color: "black"
        }
    }

    // The parent's own rectangle: cut out of the result.
    Item {
        id: hole
        visible: false
        layer.enabled: true
        x: caster.x
        y: caster.y
        width: caster.width
        height: caster.height

        Rectangle {
            x: glow.pad
            y: glow.pad
            width: glow.width
            height: glow.height
            color: "white"
        }
    }

    MultiEffect {
        x: caster.x
        y: caster.y
        width: caster.width
        height: caster.height
        source: caster
        autoPaddingEnabled: false
        shadowEnabled: true
        shadowBlur: 1.0
        blurMax: Math.min(64, Math.round(glow.blur))
        shadowColor: glow.colour
        shadowHorizontalOffset: glow.offsetX + glow.away.x
        shadowVerticalOffset: glow.offsetY + glow.away.y
        maskEnabled: true
        maskInverted: true
        maskSource: hole
    }
}
