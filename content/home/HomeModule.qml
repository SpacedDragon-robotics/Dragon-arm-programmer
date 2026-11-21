// HomeModule.qml
//
// Landing page: branding at the top, the robot/project carousel in the
// middle, an editable welcome note bottom-left and an artwork slot beside it.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm
import "../common"
import "../common/galaxy"

Item {
    id: home

    signal openBlocksRequested()
    signal openRobotSelector()

    // ---- Branding ------------------------------------------------------
    Item {
        id: brandBar

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingLarge
        height: 60

        // The brand mark: the website's dragon-head logo, softly glowing.
        LogoMark {
            id: mark
            width: 52
            height: 52
            anchors.verticalCenter: parent.verticalCenter
        }

        // Eyebrow over a thin display heading (spec: 200 weight, -.02em).
        Column {
            anchors.left: mark.right
            anchors.leftMargin: Theme.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: "ROBOT PROGRAMMER"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Theme.weightLabel
                font.letterSpacing: 11 * 0.18
            }

            Text {
                text: "SpaceDragon"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 34
                font.weight: Theme.weightDisplay
                font.letterSpacing: -0.7
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingSmall

            StatusPill {
                anchors.verticalCenter: parent.verticalCenter
                state_: "ok"
                text: RobotLibrary.currentModelName.toUpperCase()
            }

            AppButton {
                text: "Open Blocks"
                variant: "primary"
                onClicked: home.openBlocksRequested()
            }
        }
    }

    // ---- Carousel ------------------------------------------------------
    RobotCarousel {
        id: carousel

        anchors.top: brandBar.bottom
        anchors.topMargin: Theme.spacingLarge
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomRow.top
        anchors.bottomMargin: Theme.spacingLarge + 18   // room for the slide dots
        anchors.leftMargin: Theme.spacingLarge
        anchors.rightMargin: Theme.spacingLarge

        onRobotSelected: function (modelId) {
            RobotLibrary.selectModel(modelId)
        }
        onOpenBlocks: home.openBlocksRequested()
        onOpenHardware: home.openRobotSelector()
    }

    // ---- Welcome note + artwork slot -----------------------------------
    Row {
        id: bottomRow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.spacingLarge
        anchors.topMargin: Theme.spacingLarge
        height: 190
        spacing: Theme.spacing

        PanelCard {
            width: Math.round((parent.width - Theme.spacing) * 0.58)
            height: parent.height
            title: "Welcome"
            subtitle: "editable – click to write your own notes"

            content: [
                ScrollView {
                    anchors.fill: parent
                    clip: true

                    TextArea {
                        id: welcomeText

                        wrapMode: TextArea.Wrap
                        selectByMouse: true
                        color: Theme.textSecondary
                        text: "Build a movement sequence for the Dragon-Arm Demo.\n\n1.  Open Blocks and drag Axis-1, Axis-2, Axis-3 or Gripper onto the timeline.\n2.  Select a block to set its absolute target angle and duration.\n3.  Open Code to generate and copy the Arduino sketch.\n\nThis is beta version of SpaceDragon app made using Claude Code.\nFor more info You can join my discord, link on website or visit my youtube channel SpaceDragon robotics"
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightBody
                        font.pixelSize: Theme.fontBody
                        background: null

                    }
                }
            ]
        }

        PanelCard {
            width: parent.width - Theme.spacing
                   - Math.round((parent.width - Theme.spacing) * 0.58)
            height: parent.height
            title: "Gallery"
            subtitle: "reserved for your renders"
            accent: Theme.accentBright

        }
    }
}
