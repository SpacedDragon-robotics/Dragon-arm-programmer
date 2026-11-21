// RobotLibrary.qml
//
// Owns the robot catalogue and the currently selected model.
//
// `currentModel` is a plain JS object. Mutating it in place would not notify
// bindings, so every setter clones, edits and re-assigns. The models are small,
// and in exchange the whole UI stays reactive without a single manual signal.

pragma Singleton
import QtQuick
import "RobotModels.js" as RobotModels
import "PlanMath.js" as PlanMath
import "Kinematics.js" as Kinematics

QtObject {
    id: library

    // Untouched factory definitions, used for the carousel and for "reset".
    readonly property var catalogue: RobotModels.allModels()

    // Working copy of the selected model, including the user's hardware edits.
    property var currentModel: RobotModels.dragonArmDemo()

    readonly property string currentModelId: currentModel ? currentModel.id : ""
    readonly property string currentModelName: currentModel ? currentModel.name : ""
    readonly property var joints: currentModel ? currentModel.joints : []

    signal modelReplaced(string modelId)

    // ---- Lookup --------------------------------------------------------

    function joint(jointId) {
        return RobotModels.findJoint(currentModel, jointId)
    }

    function jointName(jointId) {
        var j = joint(jointId)
        return j ? j.name : jointId
    }

    function jointAccent(jointId) {
        var j = joint(jointId)
        return j ? j.accent : "#8B5CF6"
    }

    function jointIndex(jointId) {
        for (var i = 0; i < currentModel.joints.length; ++i) {
            if (currentModel.joints[i].id === jointId)
                return i
        }
        return -1
    }

    function isGripper(jointId) {
        var j = joint(jointId)
        return !!j && j.role === "gripper"
    }

    readonly property bool isStepper:
        !!currentModel && currentModel.driveType === "stepper"

    // ---- Tool moves ----------------------------------------------------
    // Available when the model describes its geometry (see Kinematics.js).

    readonly property bool hasKinematics: Kinematics.supports(currentModel)

    // [{ id, name, glyph, axis }] -- the six directions, in palette order.
    readonly property var moveDirections: hasKinematics ? Kinematics.DIRECTIONS : []

    readonly property string moveAccent:
        hasKinematics && currentModel.kinematics.moveAccent
        ? currentModel.kinematics.moveAccent : "#8B5CF6"

    function moveDirection(directionId) {
        return Kinematics.direction(directionId)
    }

    // "↑ Up", for chips, cards and the drag ghost.
    function moveLabel(directionId) {
        var d = Kinematics.direction(directionId)
        return d ? d.glyph + " " + d.name : "Move"
    }

    // Joint ids a move in this direction drives, in lane order.
    function moveAxes(directionId) {
        return Kinematics.moveAxes(currentModel, directionId)
    }

    // Rig rotation for the 3D view, in the CAD's own frame.
    function rigAngle(jointId, angle) {
        var j = joint(jointId)
        return j ? Kinematics.rigAngle(j, angle) : 0
    }

    // ...and back: the axis angle that turns the rig joint by `rig` degrees.
    // Used when the user turns a joint by dragging it in the 3D view.
    function angleFromRig(jointId, rig) {
        var j = joint(jointId)
        return j ? Kinematics.angleFromRig(j, rig) : 0
    }

    // Tool point for a pose given in RobotLibrary.joints order, in the robot
    // frame (mm; X forward, Y left, Z up). null without a geometry description.
    function toolPoint(pose) {
        if (!hasKinematics)
            return null
        var p = {}
        for (var i = 0; i < currentModel.joints.length; ++i) {
            var j = currentModel.joints[i]
            p[j.id] = i < pose.length ? pose[i] : j.homeAngle
        }
        var f = Kinematics.forward(currentModel, p)
        return { x: f.x, y: f.y, z: f.z }
    }

    // How this joint is wired, in one short label. Centralised so the palette,
    // the timeline lanes and the config page never branch on drive type
    // themselves.
    function wiringLabel(jointId) {
        var j = joint(jointId)
        if (!j)
            return ""
        if (isStepper)
            return "D" + j.stepPin + "/D" + j.dirPin
        return "ch " + j.channel
    }

    // Longer form for the palette: wiring plus reachable travel.
    function jointSummary(jointId) {
        var j = joint(jointId)
        if (!j)
            return ""
        if (j.role === "gripper")
            return "Grip / Release"
        return wiringLabel(jointId) + " · " + j.mechMin + "–" + j.mechMax + "°"
    }

    // Two axes must never share a STEP or DIR pin.
    function pinInUse(pin, exceptJointId) {
        if (!isStepper)
            return ""
        for (var i = 0; i < currentModel.joints.length; ++i) {
            var j = currentModel.joints[i]
            if (j.id === exceptJointId)
                continue
            if (j.stepPin === pin || j.dirPin === pin)
                return j.name
        }
        return ""
    }

    function gripperCommand(jointId, commandId) {
        return RobotModels.gripperCommand(joint(jointId), commandId)
    }

    // Absolute angle a gripper command maps to, or NaN for a normal axis.
    function commandAngle(jointId, commandId) {
        var cmd = gripperCommand(jointId, commandId)
        return cmd ? cmd.angle : NaN
    }

    function naturalDuration(fromAngle, toAngle) {
        return PlanMath.naturalDuration(currentModel, fromAngle, toAngle)
    }

    // ---- Selection -----------------------------------------------------

    function selectModel(modelId) {
        if (currentModel && currentModel.id === modelId)
            return
        currentModel = RobotModels.clone(RobotModels.modelById(modelId))
        modelReplaced(currentModel.id)
    }

    function resetHardwareToDefaults() {
        currentModel = RobotModels.clone(RobotModels.modelById(currentModel.id))
    }

    // ---- Hardware editing ----------------------------------------------
    // All of these keep the model a value type: clone, edit, re-assign.

    function setModelProperty(key, value) {
        var next = RobotModels.clone(currentModel)
        next[key] = value

        // Microstepping and full-step count feed every axis's resolution, and
        // resolution in turn sets the floor on the encoder tolerance: a
        // tolerance finer than one step makes the axis hunt by +/-1 step.
        if (next.driveType === "stepper"
                && (key === "microsteps" || key === "motorFullStepsPerRev")) {
            var stepsPerMotorRev = next.motorFullStepsPerRev * next.microsteps
            for (var i = 0; i < next.joints.length; ++i) {
                var j = next.joints[i]
                j.stepsPerDegree = (stepsPerMotorRev * j.gearRatio) / 360.0
                var base = j.toleranceBaseDeg !== undefined
                        ? j.toleranceBaseDeg : j.toleranceDeg
                j.toleranceDeg = RobotModels.resolveTolerance(base, j.stepsPerDegree)
            }
        }

        currentModel = next
    }

    function setJointProperty(jointId, key, value) {
        var next = RobotModels.clone(currentModel)
        var j = RobotModels.findJoint(next, jointId)
        if (!j)
            return
        j[key] = value

        // Keep dependent values consistent so the UI can never show an
        // impossible combination.
        if (key === "mechMin" && j.mechMax < value)
            j.mechMax = value
        if (key === "mechMax" && j.mechMin > value)
            j.mechMin = value

        if (next.driveType === "stepper") {
            // Steppers have no separate datasheet command range: the mechanical
            // limits ARE the range, so the angle sliders must follow them.
            j.nominalMin = j.mechMin
            j.nominalMax = j.mechMax

            // Steps per degree is derived, not stored independently. Letting it
            // go stale after a gearing change would silently corrupt every
            // generated step count.
            if (key === "gearRatio") {
                var stepsPerMotorRev = next.motorFullStepsPerRev * next.microsteps
                j.stepsPerDegree = (stepsPerMotorRev * j.gearRatio) / 360.0
                var base = j.toleranceBaseDeg !== undefined
                        ? j.toleranceBaseDeg : j.toleranceDeg
                j.toleranceDeg = RobotModels.resolveTolerance(base, j.stepsPerDegree)
            }

            // A hand-typed tolerance becomes the new floor, but still cannot go
            // below one step.
            if (key === "toleranceDeg") {
                j.toleranceBaseDeg = value
                j.toleranceDeg = RobotModels.resolveTolerance(value, j.stepsPerDegree)
            }
        }

        j.homeAngle = Math.max(j.mechMin, Math.min(j.mechMax, j.homeAngle))

        currentModel = next
    }

    // Two joints must never share a PCA9685 channel.
    function channelInUse(channel, exceptJointId) {
        for (var i = 0; i < currentModel.joints.length; ++i) {
            var j = currentModel.joints[i]
            if (j.id !== exceptJointId && j.channel === channel)
                return j.name
        }
        return ""
    }

    function setConstraintProperty(constraintId, key, value) {
        var next = RobotModels.clone(currentModel)
        for (var i = 0; i < next.constraints.length; ++i) {
            if (next.constraints[i].id === constraintId) {
                next.constraints[i][key] = value
                break
            }
        }
        currentModel = next
    }

    function constraintById(constraintId) {
        for (var i = 0; i < currentModel.constraints.length; ++i) {
            if (currentModel.constraints[i].id === constraintId)
                return currentModel.constraints[i]
        }
        return null
    }
}
