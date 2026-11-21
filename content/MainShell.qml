// MainShell.qml
//
// Two-panel frame: a fixed navigation sidebar on the left and the active
// module on the right. Switching modules never touches the sidebar.
//
// Also hosts the things that must sit above or below everything else:
//   * the galaxy scene behind it all and the fireflies above the content
//     (Galaxy theme, content/common/galaxy)
//   * the drag proxy that carries palette / timeline drags to their DropAreas
//   * the robot model dialog

import QtQuick
import DragonArm
import "common"
import "common/galaxy"
import "nav"
import "home"
import "blocks"
import "code"
import "view3d"

Item {
    id: shell

    // The theme's light comes from the cursor: publish where it is. Passive,
    // so it never takes an event from anything underneath.
    HoverHandler {
        id: pointer
    }
    Binding { target: AppState; property: "pointerX"; value: pointer.point.position.x }
    Binding { target: AppState; property: "pointerY"; value: pointer.point.position.y }
    Binding { target: AppState; property: "pointerInside"; value: pointer.hovered }

    GalaxyBackground {
        anchors.fill: parent
    }

    Item {
        id: frame
        anchors.fill: parent

        // A floating glass panel; the modules pad themselves, so the
        // workspace starts right at its edge.
        NavSidebar {
            id: sidebar
            x: Theme.spacing
            y: Theme.spacing
            width: Theme.sidebarWidth
            height: parent.height - 2 * Theme.spacing
            onRobotModelRequested: robotDialog.open()
        }

        Item {
            id: workspace
            anchors.left: sidebar.right
            anchors.right: parent.right
            height: parent.height

            // Modules are kept alive so the timeline keeps its scroll position
            // and the code view its selection while the user navigates away.
            HomeModule {
                anchors.fill: parent
                visible: AppState.currentModule === AppState.moduleHome
                onOpenBlocksRequested: AppState.showModule(AppState.moduleBlocks)
                onOpenRobotSelector: robotDialog.open()
            }

            BlocksModule {
                anchors.fill: parent
                visible: AppState.currentModule === AppState.moduleBlocks
            }

            CodeModule {
                anchors.fill: parent
                visible: AppState.currentModule === AppState.moduleCode
            }

            View3DModule {
                anchors.fill: parent
                visible: AppState.currentModule === AppState.moduleView3d
            }
        }
    }

    // Above the content, below drags and dialogs. Takes no input.
    FireflyLayer {
        anchors.fill: parent
        z: 500
    }

    // ---- Drag proxy ----------------------------------------------------
    //
    // A single item follows the cursor for every drag in the application.
    // Drop targets react to it through DropArea, which keeps hit-testing out
    // of the palette and the timeline entirely.

    Item {
        id: dragProxy

        width: 1
        height: 1
        x: AppState.dragX
        y: AppState.dragY
        z: 1000

        Drag.active: AppState.dragging
        Drag.hotSpot.x: 0
        Drag.hotSpot.y: 0
        Drag.keys: AppState.dragKind === AppState.dragBlock
                   ? ["dragonarm.block"]
                   : ["dragonarm.palette"]
    }

    Connections {
        target: AppState
        function onDropRequested() {
            dragProxy.Drag.drop()
        }
    }

    // Ghost that shows what is being dragged.
    DragGhost {
        x: AppState.dragX + 12
        y: AppState.dragY + 12
        z: 1001
        visible: AppState.dragging
    }

    RobotModelDialog {
        id: robotDialog
        anchors.fill: parent
        z: 2000
    }
}
