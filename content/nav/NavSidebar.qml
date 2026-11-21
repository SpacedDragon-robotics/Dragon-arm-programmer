// NavSidebar.qml
//
// The floating navigation panel (Galaxy theme .gx-sidebar): the logo at the
// top, Home / Blocks (with the nested Code entry) / 3D View, and the robot
// model picker pinned to the bottom where the template has its user block.

import QtQuick
import DragonArm
import "../common"
import "../common/galaxy"

PanelCard {
    id: sidebar

    signal robotModelRequested()

    contentMargins: 14

    content: [
        Item {
            anchors.fill: parent

            // ---- Logo ------------------------------------------------------
            Row {
                id: logo
                x: 6
                y: 6
                spacing: 12

                LogoMark {
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SPACEDRAGON"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Theme.weightStrong
                    font.letterSpacing: 15 * 0.14
                }
            }

            // ---- Primary navigation ------------------------------------------
            Column {
                id: mainNav
                anchors.top: logo.bottom
                anchors.topMargin: 26
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6

                NavButton {
                    iconName: "home"
                    label: "Home"
                    active: AppState.currentModule === AppState.moduleHome
                    onClicked: AppState.showModule(AppState.moduleHome)
                }

                NavButton {
                    iconName: "blocks"
                    label: "Blocks"
                    active: AppState.currentModule === AppState.moduleBlocks
                    onClicked: AppState.showModule(AppState.moduleBlocks)
                }

                // Nested under Blocks: only offered once the Blocks section is open.
                NavButton {
                    iconName: "code"
                    label: "Code"
                    sub: true
                    visible: AppState.blocksSectionActive
                    active: AppState.currentModule === AppState.moduleCode
                    accent: AppState.codeUpToDate ? Theme.accentBright : Theme.warning
                    onClicked: AppState.showModule(AppState.moduleCode)

                    // Marks an out-of-date sketch.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        rotation: 45
                        color: Theme.warning
                        visible: !AppState.codeUpToDate && MovementPlan.blockCount > 0
                    }
                }

                // Its own section, not part of the Blocks group: it plays the
                // plan back on the robot's 3D model.
                NavButton {
                    iconName: "cube"
                    label: "3D View"
                    active: AppState.currentModule === AppState.moduleView3d
                    onClicked: AppState.showModule(AppState.moduleView3d)
                }
            }

            // ---- Robot model (the template's user block) ------------------------
            Column {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 10

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.border
                }

                NavButton {
                    iconName: "robot"
                    label: "Robot"
                    detail: RobotLibrary.currentModelName
                    onClicked: sidebar.robotModelRequested()
                }
            }
        }
    ]
}
