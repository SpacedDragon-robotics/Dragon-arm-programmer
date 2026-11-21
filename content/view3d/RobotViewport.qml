// RobotViewport.qml
//
// The robot's 3D model in an orbitable scene. Right-drag orbits, middle-drag
// (or Shift+right-drag) pans, the wheel zooms (CameraController); "Reset
// view" puts the camera back. Left-drag on the arm poses it (PoseController),
// which writes blocks into the plan through `poseTarget`.
//
// Which model is shown comes from the robot's `view3d` id. Each rig takes
// `angles` in its own CAD frame; the conversion from the robot's axis angles
// (viewZeroDeg / viewReversed per joint) happens here, so a rig never needs
// to know anything about encoders or the app's angle conventions.

import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import DragonArm
import "../common"
import "rigs/dragon-arm-one"

Rectangle {
    id: viewport

    // Axis angles in RobotLibrary.joints order.
    property var pose: []

    // Receives the posing session (View3DModule). null = view only.
    property var poseTarget: null
    property bool posingEnabled: true
    readonly property bool posing: poser.dragging

    function cancelPose() {
        poser.cancel()
    }

    readonly property string rigId: RobotLibrary.currentModel && RobotLibrary.currentModel.view3d
                                    ? RobotLibrary.currentModel.view3d : ""
    readonly property bool hasRig: rigLoader.item !== null
    readonly property var rigItem: rigLoader.item

    // The model follows the ENCODER, not the program angle: the sketch computes
    // angle = (inverted ? 360 - raw : raw) - encoderOffsetDeg, so the physical
    // pose for a given angle moves whenever the offset or inversion changes.
    // Undoing that here keeps the model where the real arm would be.
    readonly property var rigAngles: {
        var joints = RobotLibrary.joints
        var out = []
        for (var i = 0; i < joints.length; ++i) {
            var j = joints[i]
            var a = i < pose.length ? pose[i] : j.homeAngle
            // One definition, shared with the tool-move maths (Kinematics.js),
            // so the model on screen is the geometry the moves were solved on.
            out.push(RobotLibrary.rigAngle(j.id, a))
        }
        return out
    }

    // ---- Camera defaults (millimetres; the rigs are modelled in mm) -------
    // Robot's left side ("ARM ONE" plate), slightly from the front: the view
    // the arm is usually photographed from.
    readonly property vector3d defaultTarget: Qt.vector3d(-40, 180, 0)
    readonly property real defaultDistance: 1300
    readonly property real defaultYaw: 190
    readonly property real defaultPitch: -10

    function resetView() {
        orbit.position = defaultTarget
        orbit.eulerRotation = Qt.vector3d(defaultPitch, defaultYaw, 0)
        camera.position = Qt.vector3d(0, 0, defaultDistance)
    }

    color: Theme.surface
    radius: Theme.radius
    border.width: 1
    border.color: Theme.border
    clip: true

    View3D {
        id: view

        anchors.fill: parent
        anchors.margins: 1
        visible: viewport.rigId.length > 0
        // Explicit, not just "the first camera in the scene": picking and the
        // 3D <-> screen mapping the posing relies on need it.
        camera: camera

        environment: SceneEnvironment {
            // See-through: the arm floats in the app's starfield.
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
            // Image-based light without shipping an HDR file: lifts the black
            // PLA out of the shadows and gives the metal parts something to
            // reflect.
            lightProbe: Texture {
                textureData: ProceduralSkyTextureData { }
            }
            probeExposure: 0.75
        }

        Node {
            id: orbit
            position: viewport.defaultTarget
            eulerRotation: Qt.vector3d(viewport.defaultPitch, viewport.defaultYaw, 0)

            PerspectiveCamera {
                id: camera
                position: Qt.vector3d(0, 0, viewport.defaultDistance)
                fieldOfView: 32
                clipNear: 10
                clipFar: 20000
            }
        }

        DirectionalLight {
            // Key light, high and to the front-left; the only shadow caster.
            eulerRotation: Qt.vector3d(-52, -28, 0)
            brightness: 1.1
            castsShadow: true
            shadowMapQuality: Light.ShadowMapQualityHigh
            shadowFactor: 55
            pcfFactor: 4
            softShadowQuality: Light.PCF16
        }

        DirectionalLight {
            // Rim light from behind, so the dark parts keep an outline.
            eulerRotation: Qt.vector3d(-18, 160, 0)
            brightness: 0.55
        }

        // Turntable disc: catches the shadow and gives the arm a footprint.
        // 450 mm radius, about the arm's reach. (#Cylinder is 50 units in
        // radius and 100 tall.)
        Model {
            source: "#Cylinder"
            position: Qt.vector3d(0, -1, 0)
            scale: Qt.vector3d(9, 0.02, 9)
            receivesShadows: true
            castsShadows: false
            materials: PrincipledMaterial {
                baseColor: Theme.background2    // opaque: glass colours do not suit a material
                roughness: 0.95
            }
        }

        Loader3D {
            id: rigLoader
            sourceComponent: viewport.rigId === "dragon-arm-one" ? dragonArmOneRig : null
        }

        Component {
            id: dragonArmOneRig
            DragonArmOneRig {
                angles: viewport.rigAngles
            }
        }
    }

    // Right button: the left one belongs to the posing. (Left orbits too
    // while posing is switched off.)
    CameraController {
        anchors.fill: view
        origin: orbit
        camera: camera
        leftOrbits: !poser.active
        visible: viewport.hasRig
    }

    // Above the camera controller. It only takes the left button, and only on
    // the arm or a handle; right and middle presses, the wheel and left
    // presses on the background all fall through to the camera.
    PoseController {
        id: poser
        anchors.fill: view
        visible: viewport.hasRig
        view: view
        orbit: orbit
        camera: camera
        rig: rigLoader.item
        pose: viewport.pose
        poseTarget: viewport.poseTarget
        active: viewport.posingEnabled && viewport.hasRig && viewport.poseTarget !== null
    }

    // ---- Live axis readout ------------------------------------------------
    Rectangle {
        id: readout

        visible: viewport.hasRig
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Theme.spacing
        width: readoutColumn.implicitWidth + 2 * Theme.spacing
        height: readoutColumn.implicitHeight + 2 * Theme.spacingSmall + 2
        radius: Theme.radius
        color: Theme.fade(Theme.surfaceSolid, 0.86)
        border.width: 1
        border.color: Theme.border

        Column {
            id: readoutColumn
            anchors.centerIn: parent
            spacing: 3

            Repeater {
                model: RobotLibrary.joints

                Row {
                    required property var modelData
                    required property int index
                    spacing: Theme.spacingSmall

                    Rectangle {
                        width: 8
                        height: 8
                        radius: Theme.radiusSmall
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.accent
                    }

                    Text {
                        width: 52
                        text: modelData.name
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightBody
                        font.pixelSize: Theme.fontSmall
                    }

                    Text {
                        width: 58
                        horizontalAlignment: Text.AlignRight
                        text: (index < viewport.pose.length ? viewport.pose[index] : 0).toFixed(1) + "°"
                        color: Theme.textPrimary
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontSmall
                    }
                }
            }
        }
    }

    // ---- View controls ----------------------------------------------------
    Row {
        visible: viewport.hasRig
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacing
        spacing: Theme.spacingSmall

        Rectangle {
            visible: viewport.poseTarget !== null
            anchors.verticalCenter: parent.verticalCenter
            width: poseToggle.implicitWidth + 2 * Theme.spacingSmall
            height: 30
            radius: Theme.radiusSmall
            color: Theme.fade(Theme.surfaceSolid, 0.86)
            border.width: 1
            border.color: Theme.border

            AppCheckBox {
                id: poseToggle
                anchors.centerIn: parent
                text: "Pose with the mouse"
                checked: viewport.posingEnabled
                onToggled: viewport.posingEnabled = checked
            }
        }

        AppButton {
            anchors.verticalCenter: parent.verticalCenter
            text: "Reset view"
            onClicked: viewport.resetView()
        }
    }

    Column {
        visible: viewport.hasRig
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Theme.spacing
        spacing: 2

        Text {
            anchors.right: parent.right
            visible: poser.active
            text: "Drag a segment to turn its axis · drag the tool or an arrow to move it "
                  + "in a straight line · ring: Axis-5 roll"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.weight: Theme.weightBody
            font.pixelSize: Theme.fontTiny
        }

        Text {
            anchors.right: parent.right
            visible: poser.active
            text: "Each drag adds a step at the playhead · drag again to refine it · "
                  + "Shift: move together with the last step · Esc cancels · Delete removes"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.weight: Theme.weightBody
            font.pixelSize: Theme.fontTiny
        }

        Text {
            anchors.right: parent.right
            text: (poser.active ? "Right-drag to orbit" : "Drag or right-drag to orbit")
                  + " · middle-drag or Shift+right-drag to pan · wheel to zoom"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.weight: Theme.weightBody
            font.pixelSize: Theme.fontTiny
        }
    }

    // ---- No model for this robot ------------------------------------------
    Column {
        visible: !viewport.hasRig
        anchors.centerIn: parent
        spacing: Theme.spacingSmall

        NavIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "cube"
            width: 44
            height: 44
            thickness: 1.4
            color: Theme.textMuted
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No 3D model for " + RobotLibrary.currentModelName + " yet"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.weight: Theme.weightBody
            font.pixelSize: Theme.fontTitle
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var names = []
                for (var i = 0; i < RobotLibrary.catalogue.length; ++i) {
                    if (RobotLibrary.catalogue[i].view3d)
                        names.push(RobotLibrary.catalogue[i].name)
                }
                return names.length
                        ? "Models with a 3D view: " + names.join(", ") + ". Switch under Robot."
                        : ""
            }
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.weight: Theme.weightBody
            font.pixelSize: Theme.fontSmall
        }
    }
}
