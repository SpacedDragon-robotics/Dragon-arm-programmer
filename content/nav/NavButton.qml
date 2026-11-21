// NavButton.qml -- one entry in the navigation sidebar.
//
// Galaxy theme (.gx-nav-item): icon and label in a row, muted at rest.
// Hover lights it (white frame, purple light from below); the active entry
// is white on a purple fade with a glowing accent bar on its left edge, and
// fireflies gather around it.

import QtQuick
import DragonArm
import "../common"
import "../common/galaxy"

Item {
    id: button

    property string iconName: "home"
    property string label: ""
    property string detail: ""          // optional second line, muted
    property bool active: false
    property bool sub: false
    property color accent: Theme.accentBright

    signal clicked()

    readonly property bool lit: mouse.containsMouse

    width: parent ? parent.width : Theme.sidebarWidth
    height: sub ? 38 : (detail.length > 0 ? 54 : 46)

    Rectangle {
        id: face
        anchors.fill: parent
        anchors.leftMargin: button.sub ? 22 : 0
        radius: Theme.radius
        color: button.lit && !button.active ? Theme.surfaceHover : "transparent"
        border.width: 1
        border.color: button.lit ? Theme.fade(Theme.white, 0.5) : "transparent"

        Behavior on color {
            ColorAnimation { duration: 250 }
        }

        // Active: linear-gradient(90deg, hsl(268 72% 60% / .22), transparent)
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            visible: button.active
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.fade(Theme.activeTint, 0.22) }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        // Active: 3 px accent bar, inset 22 % top and bottom, glowing.
        Rectangle {
            x: -1
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: button.active ? parent.height * 0.56 : 0
            color: button.accent

            Behavior on height {
                NumberAnimation { duration: Theme.hoverMs; easing.type: Theme.easing }
            }

            Rectangle {
                x: parent.width
                width: 12
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.fade(button.accent, 0.45) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }

        // Hover: purple light from below.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 1
            height: 12
            opacity: button.lit ? 1 : 0
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Theme.fade(Theme.underGlowInner, 0.6 * Theme.underGlow) }
            }
            Behavior on opacity {
                NumberAnimation { duration: Theme.hoverMs; easing.type: Theme.easing }
            }
        }

        GlowShadow {
            opacity: button.lit ? 1 : 0
            colour: Theme.fade(Theme.underGlowColor, 0.55 * Theme.underGlow)
            offsetY: 12
            blur: 26
            spread: -8
            Behavior on opacity {
                NumberAnimation { duration: Theme.hoverMs; easing.type: Theme.easing }
            }
        }

        SpotLight {
            innerLight: false
        }

        FireflyEmitter {
            active: button.active
            hovered: button.lit
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: button.sub ? 12 : 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: button.sub ? 10 : 14

            NavIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: button.iconName
                width: button.sub ? 16 : 20
                height: width
                opacity: 0.85
                color: button.active ? Theme.white
                                     : (button.lit ? Theme.textPrimary : Theme.textSecondary)
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: button.label
                    color: button.active ? Theme.white
                                         : (button.lit ? Theme.textPrimary : Theme.textSecondary)
                    font.family: Theme.fontFamily
                    font.pixelSize: button.sub ? Theme.fontBody : 15
                    font.weight: button.active ? Theme.weightLabel : Font.Normal
                }

                Text {
                    visible: button.detail.length > 0
                    width: face.width - 60
                    text: button.detail
                    elide: Text.ElideRight
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSmall
                    font.weight: Theme.weightBody
                }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: face
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
