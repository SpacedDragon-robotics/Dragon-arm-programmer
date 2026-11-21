// PanelCard.qml -- titled surface used for every panel in the workspace.
//
// A Galaxy-theme glass surface: translucent, square, a faint highlight
// along the top, an edge that lights up near the cursor, and a shadow that
// falls away from the cursor. The title is an "eyebrow": small, spaced
// capitals.

import QtQuick
import DragonArm
import "galaxy"

Rectangle {
    id: card

    property string title: ""
    property string subtitle: ""
    property color accent: Theme.accent
    property alias content: contentArea.data
    property int contentMargins: Theme.spacing
    readonly property alias contentItem: contentArea

    // Theme effects, on by default for panels.
    property bool castShadow: true
    property bool spotlight: true
    property bool fireflies: false

    color: Theme.surface
    radius: Theme.radiusLarge
    border.width: 1
    border.color: Theme.border

    // linear-gradient(180deg, white / .035, transparent 40%)
    gradient: Gradient {
        GradientStop { position: 0; color: Theme.blend(Theme.surface, Theme.white, 0.035) }
        GradientStop { position: 0.4; color: Theme.surface }
    }

    GlowShadow {
        visible: card.castShadow
        followCursor: true
    }

    // inset 0 1px 0 white / .05
    Rectangle {
        x: 1
        y: 1
        width: parent.width - 2
        height: 1
        color: Theme.fade(Theme.white, 0.05)
    }

    SpotLight {
        visible: card.spotlight
    }

    FireflyEmitter {
        active: card.fireflies
    }

    Item {
        id: header
        visible: card.title.length > 0
        height: visible ? 38 : 0
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing

        Rectangle {
            id: accentBar
            width: 2
            height: 13
            color: card.accent
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: titleText
            anchors.left: accentBar.right
            anchors.leftMargin: Theme.spacingSmall + 2
            anchors.verticalCenter: parent.verticalCenter
            text: card.title.toUpperCase()
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Theme.weightStrong
            font.letterSpacing: 1.8
        }

        Text {
            anchors.left: titleText.right
            anchors.leftMargin: Theme.spacing
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: card.subtitle
            color: Theme.textMuted
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontTiny
            font.weight: Theme.weightBody
        }
    }

    Item {
        id: contentArea
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: card.contentMargins
        anchors.topMargin: card.title.length > 0 ? 0 : card.contentMargins
    }
}
