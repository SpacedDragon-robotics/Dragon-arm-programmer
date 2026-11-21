// IconButton.qml -- square button carrying one NavIcon, with an optional
// tooltip. `primary` fills it with the accent gradient; `checked` marks a
// toggle as on. Galaxy theme: glass, sharp, white focus frame and purple
// under-glow on hover, like AppButton.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm
import "galaxy"

Rectangle {
    id: button

    property string icon: "play"
    property string tooltipText: ""
    property bool primary: false
    property bool checked: false
    property color accent: Theme.accent

    signal clicked()

    readonly property bool lit: enabled && mouse.containsMouse

    width: primary ? 38 : 32
    height: 32
    radius: Theme.radiusSmall
    opacity: enabled ? 1.0 : 0.45

    scale: !enabled ? 1 : (mouse.pressed ? 0.98 : (lit ? 1.045 : 1))
    Behavior on scale {
        NumberAnimation { duration: Theme.hoverMs; easing.type: Theme.easing }
    }

    color: {
        if (primary)
            return "transparent"
        if (checked)
            return Theme.accentSoft
        return lit ? Theme.surfaceHover : Theme.surface
    }
    border.width: 1
    border.color: lit ? Theme.borderFocus
                      : (checked ? accent : (primary ? Theme.fade(Theme.primaryBorder, 0.35) : Theme.border))

    Behavior on color {
        ColorAnimation { duration: 250 }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        visible: button.primary
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.primaryTop }
            GradientStop { position: 1; color: Theme.primaryBottom }
        }
    }

    // Under-glow from inside.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 12
        opacity: button.lit ? 1 : 0
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Theme.fade(Theme.underGlowInner, 0.8 * Theme.underGlow) }
        }
        Behavior on opacity {
            NumberAnimation { duration: Theme.hoverMs; easing.type: Theme.easing }
        }
    }

    SpotLight {
        innerLight: !button.primary
    }

    GlowShadow {
        opacity: button.lit || button.primary ? 1 : 0
        colour: Theme.fade(Theme.underGlowColor, (button.lit ? 0.65 : 0.3) * Theme.underGlow)
        offsetY: 12
        blur: 26
        spread: -5
        Behavior on opacity {
            NumberAnimation { duration: Theme.hoverMs; easing.type: Theme.easing }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        color: "transparent"
        border.width: 1
        border.color: Theme.fade(Theme.white, 0.35)
        visible: button.lit
    }

    FireflyEmitter {
        active: button.enabled
        hovered: button.lit
    }

    NavIcon {
        anchors.centerIn: parent
        width: 16
        height: 16
        name: button.icon
        thickness: 1.8
        color: button.primary ? Theme.white
                              : (button.checked ? Theme.accentBright
                                                : (button.lit ? Theme.textPrimary : Theme.textSecondary))
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

    ToolTip.visible: tooltipText.length > 0 && mouse.containsMouse
    ToolTip.delay: 600
    ToolTip.text: tooltipText
}
