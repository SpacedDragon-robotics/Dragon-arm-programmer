// AppButton.qml -- themed push button with three visual weights.
//
// Galaxy theme (spec section 7, .gx-btn): glass with a 1 px border and
// square corners. On hover it scales up a little, gets a white focus frame
// with a faint outer ring, glows purple around and from underneath, and
// fireflies gather on its edge. "primary" is the purple gradient with a
// white shimmer that sweeps across on hover.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm
import "galaxy"

Button {
    id: control

    // "primary" | "secondary" | "ghost"
    property string variant: "secondary"
    property color accent: Theme.accent
    property bool danger: false

    readonly property color effectiveAccent: danger ? Theme.danger : accent
    readonly property bool lit: enabled && (hovered || visualFocus)
    readonly property bool primary: variant === "primary"

    implicitHeight: 32
    implicitWidth: Math.max(88, contentLabel.implicitWidth + 28)
    hoverEnabled: true
    focusPolicy: Qt.NoFocus

    scale: !enabled ? 1 : (down ? 0.98 : (lit ? 1.045 : 1))
    Behavior on scale {
        NumberAnimation { duration: Theme.hoverMs; easing.type: Theme.easing }
    }

    background: Rectangle {
        id: face

        color: {
            if (control.primary)
                return "transparent"            // the gradient below
            if (control.variant === "ghost")
                return control.lit ? Theme.surfaceHover : "transparent"
            return control.lit ? Theme.surfaceHover : Theme.surface
        }
        border.width: control.variant === "ghost" && !control.lit ? 0 : 1
        border.color: control.lit ? Theme.borderFocus
                                  : (control.primary ? Theme.fade(Theme.primaryBorder, 0.35) : Theme.border)
        opacity: control.enabled ? 1 : 0.45
        clip: true

        Behavior on color {
            ColorAnimation { duration: 250 }
        }

        // Primary: hsl(268 72% 62%) -> hsl(268 72% 42%), or red for danger.
        Rectangle {
            anchors.fill: parent
            anchors.margins: parent.border.width
            visible: control.primary
            gradient: Gradient {
                GradientStop { position: 0; color: control.danger ? Qt.lighter(Theme.danger, 1.08) : Theme.primaryTop }
                GradientStop { position: 1; color: control.danger ? Qt.darker(Theme.danger, 1.5) : Theme.primaryBottom }
            }
        }

        // Shimmer: a diagonal white band that sweeps across on hover (.9 s).
        Rectangle {
            visible: control.primary
            width: parent.width * 0.5
            height: parent.height * 3
            y: -parent.height
            rotation: 20
            x: control.lit ? parent.width * 1.4 : -width * 1.4
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: Theme.fade(Theme.white, 0.28) }
                GradientStop { position: 1; color: "transparent" }
            }
            Behavior on x {
                enabled: control.lit
                NumberAnimation { duration: 900; easing.type: Theme.easing }
            }
        }

        // Under-glow from inside: inset 0 -14px 18px -14px hsl(268 90% 88% / .56)
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 1
            height: Math.min(14, parent.height / 2)
            opacity: control.lit ? 1 : 0
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Theme.fade(Theme.underGlowInner, 0.8 * Theme.underGlow) }
            }
            Behavior on opacity {
                NumberAnimation { duration: Theme.hoverMs; easing.type: Theme.easing }
            }
        }

        // Cursor edge glow.
        SpotLight {
            innerLight: !control.primary
        }

        // Purple light from below + accent glow around (hover only).
        GlowShadow {
            opacity: control.lit ? 1 : 0
            colour: Theme.fade(Theme.underGlowColor, 0.65 * Theme.underGlow)
            offsetY: 14
            blur: 30
            spread: -6
            Behavior on opacity {
                NumberAnimation { duration: Theme.hoverMs; easing.type: Theme.easing }
            }
        }
        GlowShadow {
            opacity: control.lit ? 1 : 0
            colour: Theme.accentGlow
            offsetY: 0
            blur: 24
            spread: 0
            Behavior on opacity {
                NumberAnimation { duration: Theme.hoverMs; easing.type: Theme.easing }
            }
        }

        // Outer ring: 0 0 0 1px white / .35
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            color: "transparent"
            border.width: 1
            border.color: Theme.fade(Theme.white, 0.35)
            visible: control.lit
        }

        FireflyEmitter {
            active: control.enabled && control.variant !== "ghost"
            hovered: control.lit
        }
    }

    contentItem: Text {
        id: contentLabel
        text: control.text
        color: {
            if (!control.enabled)
                return Theme.textMuted
            if (control.primary)
                return Theme.white
            if (control.danger)
                return control.lit ? Theme.danger : Theme.fade(Theme.danger, 0.85)
            return control.lit ? Theme.textPrimary : Theme.textSecondary
        }
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSmall
        font.weight: Theme.weightLabel
        font.letterSpacing: 0.3
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
