// RobotModelDialog.qml
//
// Robot model selection and hardware configuration.
//
// Everything the generated sketch depends on is editable here: channel
// assignments, I2C address, per-servo pulse calibration, mechanical limits and
// the mechanical constraints. Selecting a different model swaps the whole
// hardware description, which in turn changes the available blocks.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm
import "../common"
import "../common/galaxy"

Item {
    id: dialog

    property bool opened: false

    function open() { opened = true }
    function close() { opened = false }

    visible: opacity > 0
    opacity: opened ? 1 : 0
    enabled: opened

    Behavior on opacity {
        NumberAnimation { duration: 120 }
    }

    // Scrim -- also closes the dialog.
    Rectangle {
        anchors.fill: parent
        color: Theme.black
        opacity: 0.55

        MouseArea {
            anchors.fill: parent
            onClicked: dialog.close()
        }
    }

    Rectangle {
        id: panel

        anchors.centerIn: parent
        width: Math.min(900, dialog.width - 80)
        height: Math.min(660, dialog.height - 60)
        radius: Theme.radiusLarge
        // Solid, not glass: a dialog over busy content must hide it.
        color: Theme.surfaceSolid
        border.width: 1
        border.color: Theme.borderStrong
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.blend(Theme.surfaceSolid, Theme.white, 0.035) }
            GradientStop { position: 0.4; color: Theme.surfaceSolid }
        }

        SpotLight { }

        // Swallow clicks so they do not reach the scrim.
        MouseArea {
            anchors.fill: parent
        }

        // ---- Header ----------------------------------------------------
        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 62

            Column {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingLarge
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "Robot model"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitle
                    font.weight: Theme.weightStrong
                }

                Text {
                    text: "Hardware description used by the blocks, the validator and the generator"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.weight: Theme.weightBody
                    font.pixelSize: Theme.fontTiny
                }
            }

            AppButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingLarge
                anchors.verticalCenter: parent.verticalCenter
                text: "Close"
                variant: "ghost"
                onClicked: dialog.close()
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Theme.border
            }
        }

        // ---- Model list ------------------------------------------------
        Rectangle {
            id: modelList
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.bottom: footer.top
            width: 232
            color: Theme.surfaceAlt
            radius: Theme.radiusSmall

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Theme.border
            }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingSmall
                spacing: 4

                Repeater {
                    model: RobotLibrary.catalogue

                    delegate: Rectangle {
                        id: modelEntry
                        required property var modelData

                        readonly property bool selected:
                            RobotLibrary.currentModelId === modelEntry.modelData.id

                        width: parent.width
                        height: 62
                        radius: Theme.radiusSmall
                        color: selected ? Theme.accentSoft
                                        : (entryMouse.containsMouse ? Theme.surfaceHigh : "transparent")
                        border.width: 1
                        border.color: selected ? Theme.accent : "transparent"

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: modelEntry.modelData.name
                                color: modelEntry.selected ? Theme.accentBright : Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightStrong
                            }

                            Text {
                                width: parent.width
                                text: modelEntry.modelData.tagline
                                color: Theme.textMuted
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.weight: Theme.weightBody
                                font.pixelSize: Theme.fontTiny
                            }
                        }

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: RobotLibrary.selectModel(modelEntry.modelData.id)
                        }
                    }
                }

                // Room for the models that come next.
                Rectangle {
                    width: parent.width
                    height: 54
                    radius: Theme.radiusSmall
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.border

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "More models are added in\nimports/DragonArm/RobotModels.js"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightBody
                        font.pixelSize: Theme.fontTiny
                    }
                }
            }
        }

        // ---- Configuration ---------------------------------------------
        ScrollView {
            id: configScroll
            anchors.top: header.bottom
            anchors.left: modelList.right
            anchors.right: parent.right
            anchors.bottom: footer.top
            clip: true
            contentWidth: availableWidth

            Column {
                id: configColumn
                width: configScroll.availableWidth
                padding: Theme.spacingLarge
                spacing: Theme.spacing

                // -- Overview ---------------------------------------------
                Text {
                    width: parent.width - 2 * Theme.spacingLarge
                    text: RobotLibrary.currentModel.description
                    wrapMode: Text.WordWrap
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.weight: Theme.weightBody
                    font.pixelSize: Theme.fontSmall
                    lineHeight: 1.3
                }

                Flow {
                    width: parent.width - 2 * Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Repeater {
                        model: [
                            { k: "Controller", v: RobotLibrary.currentModel.controller },
                            { k: "Driver", v: RobotLibrary.currentModel.driver },
                            { k: "Servos", v: RobotLibrary.currentModel.servoType },
                            { k: "Bus", v: RobotLibrary.currentModel.bus }
                        ]

                        delegate: Rectangle {
                            required property var modelData

                            width: specLabel.implicitWidth + 20
                            height: 24
                            radius: Theme.radiusSmall
                            color: Theme.surfaceAlt
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                id: specLabel
                                anchors.centerIn: parent
                                text: parent.modelData.k + ": " + parent.modelData.v
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.weight: Theme.weightBody
                                font.pixelSize: Theme.fontTiny
                            }
                        }
                    }
                }

                // -- Drivers ----------------------------------------------
                SectionHeader {
                    width: parent.width - 2 * Theme.spacingLarge
                    text: RobotLibrary.isStepper ? "Motor drivers" : "PWM driver"
                    hint: RobotLibrary.isStepper
                          ? "Shared by every axis; feeds each axis's resolution"
                          : "Shared by every servo on this arm"
                }

                // Stepper arms: step resolution and encoder reading.
                Column {
                    width: parent.width - 2 * Theme.spacingLarge
                    spacing: Theme.spacingSmall
                    visible: RobotLibrary.isStepper

                    Row {
                        spacing: Theme.spacingLarge

                        NumberField {
                            label: "Full steps/rev"
                            fieldWidth: 76
                            value: RobotLibrary.currentModel.motorFullStepsPerRev
                                   !== undefined
                                   ? RobotLibrary.currentModel.motorFullStepsPerRev : 200
                            from: 4
                            to: 1000
                            onCommitted: function (v) {
                                RobotLibrary.setModelProperty("motorFullStepsPerRev",
                                                              Math.round(v))
                            }
                        }

                        Item {
                            width: 208
                            height: 42

                            Text {
                                anchors.top: parent.top
                                text: "Step mode"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.weight: Theme.weightBody
                                font.pixelSize: Theme.fontTiny
                            }

                            Row {
                                anchors.bottom: parent.bottom
                                spacing: 4

                                Repeater {
                                    model: [
                                        { steps: 1, name: "Full · strength" },
                                        { steps: 2, name: "½ · precision" }
                                    ]

                                    delegate: Rectangle {
                                        id: stepMode
                                        required property var modelData

                                        readonly property bool active:
                                            RobotLibrary.currentModel.microsteps
                                            === stepMode.modelData.steps

                                        width: 100
                                        height: 26
                                        radius: Theme.radiusSmall
                                        color: active ? Theme.accentSoft
                                                      : (stepMouse.containsMouse
                                                         ? Theme.surfaceHover : Theme.surfaceAlt)
                                        border.width: 1
                                        border.color: active ? Theme.accent : Theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: stepMode.modelData.name
                                            color: stepMode.active ? Theme.accentBright
                                                                   : Theme.textSecondary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontTiny
                                            font.weight: (stepMode.active) ? Theme.weightStrong : Theme.weightBody
                                        }

                                        MouseArea {
                                            id: stepMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: RobotLibrary.setModelProperty(
                                                           "microsteps", stepMode.modelData.steps)
                                        }
                                    }
                                }
                            }
                        }

                        NumberField {
                            label: "Probe nudge"
                            fieldWidth: 68
                            decimals: 1
                            suffix: "°"
                            value: RobotLibrary.currentModel.calibrationProbeDeg !== undefined
                                   ? RobotLibrary.currentModel.calibrationProbeDeg : 5
                            from: 2
                            to: 45
                            onCommitted: function (v) {
                                RobotLibrary.setModelProperty("calibrationProbeDeg", v)
                            }
                        }

                        NumberField {
                            label: "Encoder samples"
                            fieldWidth: 68
                            value: RobotLibrary.currentModel.encoderSamples !== undefined
                                   ? RobotLibrary.currentModel.encoderSamples : 8
                            from: 1
                            to: 64
                            onCommitted: function (v) {
                                RobotLibrary.setModelProperty("encoderSamples", Math.round(v))
                            }
                        }
                    }

                    AppCheckBox {
                        text: "Probe each axis at startup to learn its DIR direction"
                        checked: RobotLibrary.currentModel.directionCalibration === true
                        onToggled: RobotLibrary.setModelProperty("directionCalibration", checked)
                    }

                    AppCheckBox {
                        text: "Hybrid control: encoders continuously correct the motors"
                        checked: RobotLibrary.currentModel.encoderVerifyAfterMove === true
                        onToggled: RobotLibrary.setModelProperty("encoderVerifyAfterMove", checked)
                    }

                    AppCheckBox {
                        text: "Encoder test build – motors off, stream readings only"
                        accent: Theme.warning
                        checked: RobotLibrary.currentModel.encoderMonitorMode === true
                        onToggled: RobotLibrary.setModelProperty("encoderMonitorMode", checked)
                    }

                    Text {
                        visible: RobotLibrary.currentModel.encoderMonitorMode === true
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Diagnostic build: the generated sketch leaves the drivers "
                              + "disabled, skips the probe and never runs the timeline. Turn "
                              + "each axis by hand and watch its angle follow."
                        color: Theme.warning
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightBody
                        font.pixelSize: Theme.fontTiny
                        lineHeight: 1.25
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: {
                            var m = RobotLibrary.currentModel
                            var worst = 0
                            for (var i = 0; i < m.joints.length; ++i) {
                                var d = 1.0 / m.joints[i].stepsPerDegree
                                if (d > worst)
                                    worst = d
                            }
                            return (m.microsteps === 1
                                    ? "Full step: half the pulses for the Uno to produce and more "
                                      + "torque per step. The driver still interpolates to 256 "
                                      + "microsteps internally, so motion stays smooth. "
                                    : "Half step: twice the commanded resolution, twice the "
                                      + "pulse rate. ")
                                   + "Coarsest axis is " + worst.toFixed(2)
                                   + "° per step. Step mode is set over UART at startup, "
                                   + "before the direction probe, and applies to every driver "
                                   + "on the board – they share one write-only line."
                        }
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightBody
                        font.pixelSize: Theme.fontTiny
                        lineHeight: 1.25
                    }
                }

                // Servo arms: PCA9685 settings.
                Row {
                    visible: !RobotLibrary.isStepper
                    spacing: Theme.spacingLarge

                    NumberField {
                        label: "I2C address"
                        fieldWidth: 80
                        hex: true
                        value: RobotLibrary.currentModel.i2cAddress !== undefined
                               ? RobotLibrary.currentModel.i2cAddress : 0x40
                        from: 0x40
                        to: 0x7F
                        onCommitted: function (v) {
                            RobotLibrary.setModelProperty("i2cAddress", Math.round(v))
                        }
                    }

                    NumberField {
                        label: "PWM frequency"
                        fieldWidth: 80
                        suffix: " Hz"
                        value: RobotLibrary.currentModel.pwmFrequencyHz !== undefined
                               ? RobotLibrary.currentModel.pwmFrequencyHz : 50
                        from: 24
                        to: 400
                        onCommitted: function (v) {
                            RobotLibrary.setModelProperty("pwmFrequencyHz", Math.round(v))
                        }
                    }

                    NumberField {
                        label: "Oscillator"
                        fieldWidth: 98
                        suffix: " Hz"
                        value: RobotLibrary.currentModel.oscillatorHz !== undefined
                               ? RobotLibrary.currentModel.oscillatorHz : 27000000
                        from: 23000000
                        to: 31000000
                        onCommitted: function (v) {
                            RobotLibrary.setModelProperty("oscillatorHz", Math.round(v))
                        }
                    }

                    NumberField {
                        label: "Natural speed"
                        fieldWidth: 92
                        decimals: 2
                        suffix: " s/60°"
                        value: RobotLibrary.currentModel.naturalSecondsPer60Deg
                        from: 0.01
                        to: 5
                        onCommitted: function (v) {
                            RobotLibrary.setModelProperty("naturalSecondsPer60Deg", v)
                        }
                    }
                }

                // -- Startup and motion -----------------------------------
                SectionHeader {
                    width: parent.width - 2 * Theme.spacingLarge
                    text: "Startup and motion"
                    hint: "How the sequence begins and how servos travel"
                }

                Column {
                    width: parent.width - 2 * Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    AppCheckBox {
                        visible: !RobotLibrary.isStepper
                        text: "Drive servos to their start angles on power-up (homing)"
                        checked: RobotLibrary.currentModel.startupHoming
                        onToggled: RobotLibrary.setModelProperty("startupHoming", checked)
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: RobotLibrary.isStepper
                              ? "This arm reads its absolute encoders at power-up, so it always "
                                + "knows its real pose and never needs a homing move. The first "
                                + "movement on each axis starts from where the arm actually is."
                              : (RobotLibrary.currentModel.startupHoming
                                 ? "The arm is moved to the start angles below before the "
                                   + "timeline runs. The start delay doubles as the settling time."
                                 : "No channel is driven until a servo's first movement, so the "
                                   + "arm keeps whatever pose it is already in. The start angles "
                                   + "below are still what the planner validates against.")
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightBody
                        font.pixelSize: Theme.fontTiny
                        lineHeight: 1.25
                    }

                    Row {
                        spacing: Theme.spacingLarge

                        NumberField {
                            label: "Start delay"
                            fieldWidth: 80
                            suffix: " ms"
                            value: RobotLibrary.currentModel.startDelayMs
                            from: 0
                            to: 60000
                            onCommitted: function (v) {
                                RobotLibrary.setModelProperty("startDelayMs", Math.round(v))
                            }
                        }

                        NumberField {
                            // Servo-only: steppers hold position mechanically.
                            visible: !RobotLibrary.isStepper
                            label: "Hold refresh"
                            fieldWidth: 80
                            suffix: " ms"
                            value: RobotLibrary.currentModel.holdRefreshMs
                            from: 0
                            to: 10000
                            onCommitted: function (v) {
                                RobotLibrary.setModelProperty("holdRefreshMs", Math.round(v))
                            }
                        }

                        Item {
                            // Stepper motion is always an S-curve ramp, and
                            // the ramp is set per block in the inspector.
                            visible: !RobotLibrary.isStepper
                            width: visible ? 190 : 0
                            height: 42

                            Text {
                                anchors.top: parent.top
                                text: "Motion profile"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.weight: Theme.weightBody
                                font.pixelSize: Theme.fontTiny
                            }

                            Row {
                                anchors.bottom: parent.bottom
                                spacing: 4

                                Repeater {
                                    model: [
                                        { id: "easeInOut", name: "Eased" },
                                        { id: "linear", name: "Linear" }
                                    ]

                                    delegate: Rectangle {
                                        id: profileButton
                                        required property var modelData

                                        readonly property bool active:
                                            RobotLibrary.currentModel.motionProfile
                                            === profileButton.modelData.id

                                        width: 74
                                        height: 26
                                        radius: Theme.radiusSmall
                                        color: active ? Theme.accentSoft
                                                      : (profileMouse.containsMouse
                                                         ? Theme.surfaceHover : Theme.surfaceAlt)
                                        border.width: 1
                                        border.color: active ? Theme.accent : Theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: profileButton.modelData.name
                                            color: profileButton.active ? Theme.accentBright
                                                                        : Theme.textSecondary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSmall
                                            font.weight: (profileButton.active) ? Theme.weightStrong : Theme.weightBody
                                        }

                                        MouseArea {
                                            id: profileMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: RobotLibrary.setModelProperty(
                                                           "motionProfile",
                                                           profileButton.modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    AppCheckBox {
                        visible: !RobotLibrary.isStepper
                        text: "Cut PWM when the sequence ends (servos go limp)"
                        checked: RobotLibrary.currentModel.releaseAfterSequence
                        onToggled: RobotLibrary.setModelProperty("releaseAfterSequence", checked)
                    }

                    Text {
                        visible: RobotLibrary.isStepper
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Each movement's acceleration ramp is set per block, in the "
                              + "block inspector on the Blocks page."
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightBody
                        font.pixelSize: Theme.fontTiny
                    }
                }

                // -- Servos -----------------------------------------------
                SectionHeader {
                    width: parent.width - 2 * Theme.spacingLarge
                    text: "Servo channels and calibration"
                    hint: "Each servo is calibrated independently"
                }

                Repeater {
                    model: RobotLibrary.joints

                    delegate: JointConfigRow {
                        required property var modelData
                        width: configColumn.width - 2 * Theme.spacingLarge
                        joint: modelData
                    }
                }

                // -- Constraints ------------------------------------------
                SectionHeader {
                    width: parent.width - 2 * Theme.spacingLarge
                    text: "Mechanical constraints"
                    hint: "Re-tune once the real arm is measured"
                }

                Repeater {
                    model: RobotLibrary.currentModel.constraints

                    delegate: Rectangle {
                        id: constraintRow
                        required property var modelData

                        readonly property bool tunable:
                            constraintRow.modelData.type === "angleDifference"

                        width: configColumn.width - 2 * Theme.spacingLarge
                        height: tunable ? 92 : 52
                        radius: Theme.radiusSmall
                        color: Theme.surfaceAlt
                        border.width: 1
                        border.color: Theme.border

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spacing
                            spacing: Theme.spacingSmall

                            Row {
                                spacing: Theme.spacing

                                AppCheckBox {
                                    text: constraintRow.modelData.title
                                    checked: constraintRow.modelData.enabled
                                    onToggled: RobotLibrary.setConstraintProperty(
                                                   constraintRow.modelData.id, "enabled", checked)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: constraintRow.modelData.description
                                    color: Theme.textMuted
                                    font.family: Theme.monoFamily
                                    font.pixelSize: Theme.fontTiny
                                }
                            }

                            // Only the spread rule has numbers to tune; an
                            // ordering rule is on or off.
                            Row {
                                spacing: Theme.spacingLarge
                                visible: constraintRow.tunable
                                enabled: constraintRow.modelData.enabled
                                opacity: enabled ? 1 : 0.45

                                NumberField {
                                    label: "Minimum difference"
                                    fieldWidth: 72
                                    suffix: "°"
                                    // Bindings still evaluate while hidden, and
                                    // an ordering rule has no difference fields.
                                    value: constraintRow.tunable
                                           ? constraintRow.modelData.minDifference : 0
                                    from: 0
                                    to: 180
                                    onCommitted: function (v) {
                                        RobotLibrary.setConstraintProperty(
                                            constraintRow.modelData.id, "minDifference", v)
                                    }
                                }

                                NumberField {
                                    label: "Maximum difference"
                                    fieldWidth: 72
                                    suffix: "°"
                                    value: constraintRow.tunable
                                           ? constraintRow.modelData.maxDifference : 180
                                    from: 0
                                    to: 180
                                    onCommitted: function (v) {
                                        RobotLibrary.setConstraintProperty(
                                            constraintRow.modelData.id, "maxDifference", v)
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    width: 1
                    height: Theme.spacing
                }
            }
        }

        // ---- Footer ----------------------------------------------------
        Item {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 56

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Theme.border
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingLarge
                anchors.verticalCenter: parent.verticalCenter
                text: MovementPlan.blockCount > 0
                      ? "Changes revalidate the timeline immediately."
                      : "Timeline is empty."
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.weight: Theme.weightBody
                font.pixelSize: Theme.fontTiny
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingLarge
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingSmall

                AppButton {
                    text: "Reset hardware"
                    variant: "secondary"
                    onClicked: RobotLibrary.resetHardwareToDefaults()
                }

                AppButton {
                    text: "Done"
                    variant: "primary"
                    onClicked: dialog.close()
                }
            }
        }
    }
}
