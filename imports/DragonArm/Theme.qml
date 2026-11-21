// Theme.qml
//
// Single source of truth for colours, spacing and typography.
// Nothing else in the application should hard-code a colour.
//
// The look is the "Galaxy Theme" (D:\Claude\Galaxy Theme\GALAXY-THEME.md):
// a dark, mostly GREY space scene with a little strong purple used only as
// an accent, sharp square corners, thin Manrope type, and light that comes
// from the cursor. Every colour below is a value from that spec's table
// (hue 268, saturation 72 %, 4 % purple tint in the greys).
//
// Surfaces are GLASS: translucent, so the starfield behind the app shows
// through. That is why blend() composites properly instead of mixing RGB --
// a translucent base would otherwise pull every tint towards white.

pragma Singleton
import QtQuick

QtObject {
    id: theme

    // ---- Knobs (the spec's names) -----------------------------------------
    // Corner roundness in px: 0 = sharp, which is the approved look.
    readonly property real round: 0

    // ---- Background --------------------------------------------------------
    readonly property color backgroundDeep: "#0D0C0D"     // --gx-bg
    readonly property color background2: "#171618"       // --gx-bg-2, opaque

    // ---- Surfaces (glass) ----------------------------------------------------
    readonly property color surface: "#0EBFBDC1"          // --gx-surface: hsl(268 4% 75% / .055)
    readonly property color surfaceAlt: "#14BFBDC1"       // a step up, for rows and lanes
    readonly property color surfaceHigh: "#1FCFCDD1"      // inputs, raised wells
    readonly property color surfaceHover: "#17DAD8DB"     // --gx-surface-hover: hsl(268 4% 85% / .09)
    readonly property color border: "#14FFFFFF"           // --gx-border: white / .08
    readonly property color borderStrong: "#2EFFFFFF"     // white / .18
    readonly property color borderFocus: "#E6FFFFFF"      // --gx-border-focus: white / .9
    // Opaque panel for things that must hide what is behind them (dialogs).
    readonly property color surfaceSolid: "#141315"

    // ---- Text ----------------------------------------------------------------
    readonly property color textPrimary: "#EDECEF"        // --gx-text
    readonly property color textSecondary: "#A39EA9"      // --gx-muted
    readonly property color textMuted: "#6B6670"          // --gx-dim

    // ---- Brand (purple, accents only) ----------------------------------------
    readonly property color accent: "#8F47E1"             // --gx-accent-strong: fills, bars
    readonly property color accentBright: "#AF7BEA"       // --gx-accent: text, highlights
    readonly property color accentDeep: "#611DAF"         // --gx-accent-deep
    readonly property color accentSoft: "#2E9B5BE5"       // hsl(268 72% 60% / .18): active tint
    readonly property color accentGlow: "#59A46BE8"       // --gx-accent-glow: hsl(268 72% 65% / .35)
    readonly property color accentEdge: "#F2D9C7FA"       // edge-glow core: hsl(268 90% 85% / .95)
    // Primary button gradient, top -> bottom, and its border.
    readonly property color primaryTop: "#9958E4"
    readonly property color primaryBottom: "#661EB8"
    readonly property color primaryBorder: "#D9C2F7"      // used at .35
    // Light under hovered items: outer glow hsl(268 72% 62%), inner rim
    // hsl(268 90% 88%); the active nav fade hsl(268 72% 60%).
    readonly property color underGlowColor: "#9D5BE6"
    readonly property color underGlowInner: "#E2CCFB"
    readonly property color activeTint: "#9B5BE5"

    // ---- The sky (galaxy components) --------------------------------------
    readonly property color starColor: "#F4F1FA"
    readonly property color bokehColor: "#C4B6DC"         // purple-grey dust
    readonly property color fireflyPurple: "#AF7BEA"      // hsl(268 72% 70%)
    readonly property color fireflyWhite: "#EEEBF2"       // hsl(268 30% 93%)

    readonly property color white: "#FFFFFF"
    readonly property color black: "#000000"

    // ---- Status (functional colours; kept clear and readable) ----------------
    readonly property color danger: "#F0546F"
    readonly property color dangerSoft: "#2EF0546F"
    readonly property color warning: "#E0A84A"
    readonly property color warningSoft: "#26E0A84A"
    readonly property color success: "#4ACB8F"
    readonly property color successSoft: "#244ACB8F"

    // 3D gizmo axes, in the convention every 3D tool uses: X red, Y green,
    // Z blue. (X forward, Y left, Z up in the robot's own frame.)
    readonly property color axisX: "#F0546F"
    readonly property color axisY: "#4ACB82"
    readonly property color axisZ: "#5B9BF5"

    // ---- Light & shadow (the spec's engine defaults) ---------------------------
    readonly property real cursorLight: 0.14              // cursor light opacity
    readonly property real cursorRadius: 50               // px
    readonly property real shadowAlpha: 0.55
    readonly property real shadowDistance: 18             // px, away from the cursor
    readonly property real underGlow: 0.7                 // light under hovered items
    readonly property int fireflies: 40                   // alive at once
    readonly property real hoverBoost: 1.5

    // ---- Motion ----------------------------------------------------------------
    // cubic-bezier(.2,.8,.2,1) is closest to OutQuint.
    readonly property int easing: Easing.OutQuint
    readonly property int hoverMs: 350

    // ---- Metrics ----------------------------------------------------------------
    readonly property real radiusSmall: round
    readonly property real radius: round
    readonly property real radiusLarge: round * 1.6

    readonly property int spacingTiny: 4
    readonly property int spacingSmall: 8
    readonly property int spacing: 14
    readonly property int spacingLarge: 22

    readonly property int sidebarWidth: 224

    // ---- Typography ----------------------------------------------------------------
    // Manrope ships with the app (content/fonts, loaded by App.qml).
    readonly property string fontFamily: "Manrope"
    readonly property string monoFamily: "Consolas"

    // Thin and airy: 300 for text, 200 for big headings, 500-600 only for
    // small labels.
    readonly property int weightDisplay: Font.ExtraLight   // 200
    readonly property int weightBody: Font.Light           // 300
    readonly property int weightLabel: Font.Medium         // 500
    readonly property int weightStrong: Font.DemiBold      // 600

    readonly property int fontTiny: 10
    readonly property int fontSmall: 12
    readonly property int fontBody: 13
    readonly property int fontTitle: 17
    readonly property int fontDisplay: 28

    // ---- Helpers -------------------------------------------------------------------

    // `over` painted at `amount` on top of `base` (Porter-Duff "over"). With
    // an opaque base this is a plain mix; with glass it keeps the tint's own
    // hue instead of washing it towards the glass's white.
    function blend(base, over, amount) {
        var a = Math.max(0, Math.min(1, amount))
        var outA = a + base.a * (1 - a)
        if (outA <= 0)
            return Qt.rgba(0, 0, 0, 0)
        var k = base.a * (1 - a)
        return Qt.rgba((over.r * a + base.r * k) / outA,
                       (over.g * a + base.g * k) / outA,
                       (over.b * a + base.b * k) / outA,
                       outA)
    }

    function fade(c, alpha) {
        return Qt.rgba(c.r, c.g, c.b, alpha)
    }

    // Joint accents arrive as strings from the robot model; this makes them
    // colours that blend() / fade() can work with.
    function colour(c) {
        return Qt.lighter(c, 1.0)
    }
}
