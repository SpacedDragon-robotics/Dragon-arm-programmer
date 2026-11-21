// RobotCarousel.qml
//
// Horizontal carousel of robot models and project slots. The slide list is
// built from the robot catalogue, so a new entry in RobotModels.js shows up
// here without any change to this file.

import QtQuick
import DragonArm
import "../common"

Item {
    id: carousel

    signal robotSelected(string modelId)
    signal openBlocks()
    signal openHardware()

    readonly property var slides: buildSlides()

    function buildSlides() {
        var out = []
        var models = RobotLibrary.catalogue

        for (var i = 0; i < models.length; ++i) {
            var m = models[i]
            out.push({
                kind: "robot",
                modelId: m.id,
                badge: "ROBOT MODEL",
                title: m.name,
                subtitle: m.description,
                image: m.image,
                artCaption: m.name + " render",
                artPath: "content/images/" + m.id + ".png",
                accent: "#A78BFA",
                specs: [
                    m.joints.length + " servo channels",
                    m.servoType,
                    m.driver,
                    m.controller
                ]
            })
        }

        // Slot kept for the projects that come later.
        out.push({
            kind: "placeholder",
            modelId: "",
            badge: "PROJECT",
            title: "Your next project",
            subtitle: "Space for a saved movement plan, a photo of the build or a 3D preview. "
                      + "Drop the artwork into content/images and extend buildSlides() in "
                      + "RobotCarousel.qml.",
            image: "",
            artCaption: "Project preview placeholder",
            artPath: "content/images/project-01.png",
            accent: "#4FD1C5",
            specs: ["Reserved"]
        })

        return out
    }

    function next() {
        if (view.currentIndex < view.count - 1)
            view.currentIndex++
        else
            view.currentIndex = 0
    }

    function previous() {
        if (view.currentIndex > 0)
            view.currentIndex--
        else
            view.currentIndex = view.count - 1
    }

    ListView {
        id: view

        anchors.fill: parent
        anchors.leftMargin: 52
        anchors.rightMargin: 52

        orientation: ListView.Horizontal
        model: carousel.slides
        spacing: Theme.spacing
        clip: true

        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: width
        highlightMoveDuration: 220

        delegate: CarouselSlide {
            required property var modelData
            required property int index

            width: view.width
            height: view.height
            slideData: modelData
            current: index === view.currentIndex

            onPrimaryClicked: {
                if (RobotLibrary.currentModelId === modelData.modelId)
                    carousel.openBlocks()
                else
                    carousel.robotSelected(modelData.modelId)
            }
            onSecondaryClicked: carousel.openHardware()
        }
    }

    // ---- Navigation controls -------------------------------------------
    CarouselArrow {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        direction: "chevronLeft"
        onActivated: carousel.previous()
    }

    CarouselArrow {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        direction: "chevronRight"
        onActivated: carousel.next()
    }

    // ---- Slide indicator -----------------------------------------------
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -18
        spacing: 6

        Repeater {
            model: carousel.slides.length

            delegate: Rectangle {
                required property int index

                width: index === view.currentIndex ? 20 : 7
                height: 7
                radius: Theme.radiusSmall
                color: index === view.currentIndex ? Theme.accent : Theme.border

                Behavior on width {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -5
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.currentIndex = parent.index
                }
            }
        }
    }
}
