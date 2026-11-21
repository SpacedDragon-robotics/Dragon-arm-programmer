// CarouselSlide.qml -- one card in the home carousel.

import QtQuick
import DragonArm
import "../common"

Rectangle {
    id: slide

    property var slideData: null
    property bool current: false

    signal primaryClicked()
    signal secondaryClicked()

    readonly property bool isRobot: slideData && slideData.kind === "robot"
    readonly property bool selected: isRobot && RobotLibrary.currentModelId === slideData.modelId

    radius: Theme.radiusLarge
    color: Theme.surface
    border.width: 1
    border.color: selected ? Theme.accent : Theme.border

    scale: current ? 1.0 : 0.94
    opacity: current ? 1.0 : 0.55

    Behavior on scale {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    Behavior on opacity {
        NumberAnimation { duration: 180 }
    }

    Row {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingLarge

        // ---- Artwork slot ----------------------------------------------
        PlaceholderArt {
            width: Math.round((parent.width - Theme.spacingLarge) * 0.52)
            height: parent.height
            source: slide.slideData && slide.slideData.image ? slide.slideData.image : ""
            caption: slide.slideData ? slide.slideData.artCaption : ""
            path: slide.slideData ? slide.slideData.artPath : ""
            accent: slide.slideData ? slide.slideData.accent : Theme.accent
        }

        // ---- Text ------------------------------------------------------
        Item {
            width: parent.width - Theme.spacingLarge
                   - Math.round((parent.width - Theme.spacingLarge) * 0.52)
            height: parent.height

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingSmall

                Row {
                    spacing: Theme.spacingSmall

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: badge.implicitWidth + 16
                        height: 20
                        radius: Theme.radiusSmall
                        color: Theme.accentSoft

                        Text {
                            id: badge
                            anchors.centerIn: parent
                            text: slide.slideData ? slide.slideData.badge : ""
                            color: Theme.accentBright
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontTiny
                            font.weight: Theme.weightStrong
                            font.letterSpacing: 0.6
                        }
                    }

                    StatusPill {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: slide.selected
                        state_: "ok"
                        text: "SELECTED"
                    }
                }

                Text {
                    width: parent.width
                    text: slide.slideData ? slide.slideData.title : ""
                    color: Theme.textPrimary
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 24
                    font.weight: Theme.weightStrong
                }

                Text {
                    width: parent.width
                    text: slide.slideData ? slide.slideData.subtitle : ""
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.weight: Theme.weightBody
                    font.pixelSize: Theme.fontBody
                    lineHeight: 1.35
                }

                Item {
                    width: 1
                    height: Theme.spacingTiny
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: slide.slideData && slide.slideData.specs ? slide.slideData.specs : []

                        delegate: Rectangle {
                            required property var modelData

                            width: specText.implicitWidth + 18
                            height: 22
                            radius: Theme.radiusSmall
                            color: Theme.surfaceAlt
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                id: specText
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.weight: Theme.weightBody
                                font.pixelSize: Theme.fontTiny
                            }
                        }
                    }
                }

                Item {
                    width: 1
                    height: Theme.spacingSmall
                }

                Row {
                    spacing: Theme.spacingSmall
                    visible: slide.slideData && slide.slideData.kind !== "placeholder"

                    AppButton {
                        text: slide.selected ? "Open in Blocks" : "Select this robot"
                        variant: "primary"
                        onClicked: slide.primaryClicked()
                    }

                    AppButton {
                        text: "Hardware"
                        variant: "secondary"
                        onClicked: slide.secondaryClicked()
                    }
                }
            }
        }
    }
}
