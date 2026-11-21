// RobotModels.js
//
// Hardware catalogue. Every robot supported by the application is described
// here as plain data -- no UI, no Qt types. Adding a new arm means adding one
// more factory function and listing it in `allModels()`; nothing else in the
// application needs to change.
//
// A model's `driveType` says which actuator family it uses and therefore which
// code generator runs: "servoPwm" (PCA9685 + hobby servos) or "stepper"
// (STEP/DIR drivers with absolute encoders).
//
// Joint fields shared by both families
//   id             stable identifier used by blocks and the validator
//   name           label shown in the UI
//   role           "axis" | "gripper"
//   nominalMin/Max full command range of the actuator
//   mechMin/Max    mechanical limits of THIS robot (subset of nominal range)
//   homeAngle      assumed pose at timeline t = 0
//   inverted       true when the actuator is mounted mirrored
//   accent         block colour
//
// servoPwm only
//   channel        PCA9685 output channel (0..15)
//   minPulseUs     pulse width that corresponds to nominalMin
//   maxPulseUs     pulse width that corresponds to nominalMax
//   commands       gripper only: named absolute target angles
//
// stepper only
//   stepPin/dirPin Arduino pins driving the STEP/DIR inputs
//   encoderPin     analog pin the MT6701 OUT is wired to
//   gearRatio      motor revolutions per output revolution
//   stepsPerDegree derived: microsteps per output degree
//   encoderOffsetDeg / encoderInverted   raw encoder -> program angle
//   continuousRotation  true when the axis can turn past 360 deg
//   toleranceDeg   encoder deadband of the hybrid controller
//   trackingGain / correctionGain / maxCorrectionDegPerSec / encoderFilterMs
//                  hybrid controller tuning (see ArduinoGeneratorStepper.js)
//   maxSpeedDegPerSec / maxAccelDegPerSec2  hard limits; exceeding them
//                  does not move faster, it loses steps
//
// 3D view (only on models with a `view3d` rig)
//   model.view3d   which rig the 3D view loads ("" = none); see View3DModule
//   viewZeroDeg    raw ENCODER reading (angle + encoderOffsetDeg) at which the
//                  CAD model's built pose occurs
//   viewReversed   the CAD joint turns the opposite way to the encoder
//                  rig rotation = (viewReversed ? -1 : 1) * (raw - viewZeroDeg)
//                  Tied to the encoder rather than the program angle, so
//                  changing an encoder offset moves the model the way it
//                  moves the real arm. Joint i of `joints` drives rig joint i.
//
// Tool moves (only on models with a `kinematics` entry)
//   model.kinematics   link lengths and joint geometry; documented in
//                      Kinematics.js. Its presence is what puts the Up / Down /
//                      Left / Right / Forward / Back blocks in the palette.

.pragma library

var NOMINAL_MIN = 0
var NOMINAL_MAX = 180

function dragonArmDemo() {
    return {
        id: "dragon-arm-demo",
        name: "Dragon-Arm Demo",
        tagline: "3-axis arm + servo gripper",
        description:
            "Demonstration arm driven by four MG996R servos on a PCA9685 PWM " +
            "expander. Axis-1 rotates the base, Axis-2 and Axis-3 form the " +
            "shoulder/elbow pair, and a servo gripper handles the payload.",
        controller: "Arduino Uno",
        driver: "PCA9685 (16-channel I2C PWM expander)",
        servoType: "MG996R",
        bus: "I2C (Wire)",
        // Optional: drop a PNG into content/images and point `image` at it.
        image: "",

        // No 3D model yet; the 3D view says so.
        view3d: "",

        // Actuator family. Decides which code generator runs and which
        // hardware fields the configuration page shows.
        driveType: "servoPwm",

        // ---- Bus / driver configuration (user editable) ----------------
        i2cAddress: 0x40,
        pwmFrequencyHz: 50,
        // PCA9685 internal oscillator, used by setOscillatorFrequency().
        // 25 MHz is the datasheet value; most boards measure 26-27 MHz, and
        // an uncalibrated value makes every pulse width proportionally wrong.
        oscillatorHz: 27000000,

        // ---- Startup behaviour -----------------------------------------
        // When homing is off the sketch leaves every servo alone until that
        // servo's first movement, so the arm starts from wherever it already
        // is instead of being yanked to a fixed pose on power-up.
        startupHoming: false,
        // Non-blocking pause before the timeline starts running.
        startDelayMs: 1000,

        // ---- Motion defaults -------------------------------------------
        // "Natural" duration models a plain servo.write(angle): the servo runs
        // at its own top speed. MG996R datasheet: ~0.17 s per 60 deg at 4.8 V.
        naturalSecondsPer60Deg: 0.17,
        minDuration: 0.05,
        maxDuration: 60.0,

        // "linear" | "easeInOut". Eased moves start and stop gently, which
        // stops cheap analog servos from jerking at the ends of a travel.
        motionProfile: "easeInOut",
        // Re-send the holding position this often so a single dropped I2C
        // write cannot leave a servo stuck at a stale target. 0 disables.
        holdRefreshMs: 1000,
        // Cut PWM once the sequence ends. Off by default: servos that stop
        // receiving pulses go limp instead of holding their final pose.
        releaseAfterSequence: false,

        joints: [
            {
                id: "axis1", name: "Axis-1", role: "axis",
                subtitle: "Base rotation",
                channel: 0,
                nominalMin: NOMINAL_MIN, nominalMax: NOMINAL_MAX,
                mechMin: 0, mechMax: 180,
                homeAngle: 90,
                minPulseUs: 500, maxPulseUs: 2500,
                inverted: false,
                accent: "#A78BFA"
            },
            {
                id: "axis2", name: "Axis-2", role: "axis",
                subtitle: "Shoulder",
                channel: 1,
                nominalMin: NOMINAL_MIN, nominalMax: NOMINAL_MAX,
                mechMin: 0, mechMax: 180,
                homeAngle: 60,
                minPulseUs: 500, maxPulseUs: 2500,
                inverted: false,
                accent: "#7C9CF5"
            },
            {
                id: "axis3", name: "Axis-3", role: "axis",
                subtitle: "Elbow",
                channel: 2,
                nominalMin: NOMINAL_MIN, nominalMax: NOMINAL_MAX,
                mechMin: 0, mechMax: 180,
                homeAngle: 120,
                minPulseUs: 500, maxPulseUs: 2500,
                // Mounted mirrored relative to Axis-2.
                inverted: true,
                accent: "#4FD1C5"
            },
            {
                id: "gripper", name: "Gripper", role: "gripper",
                subtitle: "Servo gripper",
                channel: 3,
                nominalMin: NOMINAL_MIN, nominalMax: NOMINAL_MAX,
                mechMin: 0, mechMax: 90,
                homeAngle: 90,
                minPulseUs: 500, maxPulseUs: 2500,
                inverted: false,
                accent: "#E9A14B",
                commands: [
                    { id: "grip",    name: "Grip",    angle: 0  },
                    { id: "release", name: "Release", angle: 90 }
                ]
            }
        ],

        // ---- Mechanical constraints ------------------------------------
        // Kept as data so the limits can be re-tuned once the real arm is
        // measured, without touching the validator.
        constraints: [
            {
                id: "axis2-axis3-difference",
                type: "angleDifference",
                enabled: true,
                jointA: "axis2",
                jointB: "axis3",
                minDifference: 40,
                maxDifference: 140,
                title: "Axis-2 / Axis-3 spread",
                description: "40° ≤ |Axis-2 − Axis-3| ≤ 140°"
            },
            {
                // Axis-2 must stay at or below Axis-3. Together with the
                // spread rule this means 40 <= Axis-3 - Axis-2 <= 140.
                id: "axis2-not-above-axis3",
                type: "angleOrder",
                enabled: true,
                jointA: "axis2",
                jointB: "axis3",
                title: "Axis-2 below Axis-3",
                description: "Axis-2 ≤ Axis-3"
            }
        ]
    }
}

// ---------------------------------------------------------------------------
// Dragon-Arm One
//
// Five NEMA 17 steppers on TMC2208 drivers, STEP/DIR from an Arduino Uno, with
// an MT6701 absolute encoder on every axis reading the FINAL (output) angle.
//
// Resolution
//   200 full steps/rev x 2 microsteps = 400 steps per motor revolution.
//   Axes 1-4 are geared 9:1  -> 3600 steps per output rev = exactly 10 per deg.
//   Axis 5 is direct drive   ->  400 steps per output rev = 1.111 per deg,
//                                i.e. 0.9 deg per step, nine times coarser.
//
// Angle convention
//   Axis-1 reads -150..+150 because its encoder's 0/360 seam sits opposite the
//   arm's centre: the usable band is 30..330 in encoder degrees, so subtracting
//   the 180 deg offset puts zero in the middle and keeps the seam out of range.
//   The other axes put zero at one end of their travel.
// ---------------------------------------------------------------------------
// Smallest encoder disagreement worth acting on, given how coarse one step is.
// Correcting an error smaller than a step makes the axis hunt: it commands one
// step, overshoots the other way, and does it again forever. Axis-5 at full
// step is 1.8 deg per step, which is why its tolerance has to grow when the
// board is switched to full step.
var TOLERANCE_STEPS = 1.4

function toleranceFloorDeg(stepsPerDegree) {
    if (!stepsPerDegree || stepsPerDegree <= 0)
        return 0
    return Math.round((TOLERANCE_STEPS / stepsPerDegree) * 10) / 10
}

function resolveTolerance(baseDeg, stepsPerDegree) {
    return Math.max(baseDeg, toleranceFloorDeg(stepsPerDegree))
}

function dragonArmOne() {
    // Default is full step; the UART block in the generated sketch applies it.
    var MICROSTEPS = 1
    var STEPS_PER_MOTOR_REV = 200 * MICROSTEPS

    function stepperAxis(cfg) {
        return {
            id: cfg.id,
            name: cfg.name,
            role: "axis",
            subtitle: cfg.subtitle,

            // --- wiring (user configurable) ---
            stepPin: cfg.stepPin,
            dirPin: cfg.dirPin,
            encoderPin: cfg.encoderPin,
            // Which chip sits in this slot. Documentation only: the shared TX
            // line is configured once per address, so every family is reached
            // regardless of which axis carries which chip.
            driverChip: cfg.chip,

            // --- transmission ---
            gearRatio: cfg.gearRatio,
            stepsPerDegree: (STEPS_PER_MOTOR_REV * cfg.gearRatio) / 360.0,

            // --- travel ---
            // Steppers have no datasheet command range the way a servo does,
            // so nominal == the full physical travel and mech is the usable
            // subset. Keeping both means the validator and the angle sliders
            // work unchanged.
            nominalMin: cfg.min, nominalMax: cfg.max,
            mechMin: cfg.min, mechMax: cfg.max,
            homeAngle: cfg.home,

            // --- encoder ---
            // Program angle = (inverted ? 360 - raw : raw) - encoderOffsetDeg
            encoderOffsetDeg: cfg.encoderOffset,
            encoderInverted: false,
            // Axis-5 can turn a full circle, so its encoder reading wraps and
            // comparisons must use the shortest arc.
            continuousRotation: !!cfg.continuous,
            // Re-sync only when the error is bigger than this, and never act on
            // an error wilder than maxCorrectionDeg (that means a bad reading).
            // toleranceBaseDeg is the user's floor; toleranceDeg is that raised
            // to at least one step, and is recomputed when microstepping changes.
            // toleranceDeg doubles as the hybrid controller's DEADBAND: encoder
            // disagreements smaller than this are ignored, so encoder noise and
            // gearbox backlash never reach the motors.
            toleranceBaseDeg: cfg.tolerance,
            toleranceDeg: resolveTolerance(
                cfg.tolerance, (STEPS_PER_MOTOR_REV * cfg.gearRatio) / 360.0),

            // --- hybrid controller ---
            // trackingGain:   1/s, how hard the motor closes a gap to the plan
            // correctionGain: 1/s, how fast the encoder pulls the step count
            //                 back onto the real arm angle
            // maxCorrectionDegPerSec: cap on that pull, so a lost-step
            //                 correction is a smooth slide, never a lurch
            // encoderFilterMs: low-pass on the encoder reading
            trackingGain: 8.0,
            correctionGain: 2.0,
            maxCorrectionDegPerSec: Math.round(cfg.maxSpeed * 0.25),
            encoderFilterMs: 15,

            // --- motion limits ---
            // Conservative starting points: a stepper asked to exceed these
            // does not go faster, it loses steps. Raise them on real hardware.
            maxSpeedDegPerSec: cfg.maxSpeed,
            maxAccelDegPerSec2: cfg.maxAccel,

            // --- 3D view ---
            // The 0 deg pose (default encoder offsets), as defined by the user:
            //   Axis-1  facing the front of the arm (= CAD J1 0)
            //   Axis-2  at its back stop: zero 70 set by the user against the
            //           real arm (= viewer J2 134.7; the CAD's first
            //           upper-arm/turret contact was estimated at 127)
            //   Axis-3  forearm at 90 deg to the upper arm, bent back (J3 +90)
            //   Axis-4  wrist parallel to the upper arm, pointing back down
            //           towards the base (J4 +90)
            //   Axis-5  pointing at the arm (taken as CAD J5 0, unverified)
            // Increasing angles move every axis forward. Ranges agree: A3
            // 0..240 = J3 +90..-150, A4 0..180 = J4 +90..-90.
            // Confirmed against the real arm (2026-11-12). There is no UI for
            // these; change them here if the CAD or the encoders change.
            viewZeroDeg: cfg.viewZero,
            viewReversed: !!cfg.viewReversed,

            // The startup probe decides the real direction sense; this is only
            // the value used before that has run.
            inverted: false,

            accent: cfg.accent
        }
    }

    return {
        id: "dragon-arm-one",
        name: "Dragon-Arm One",
        tagline: "5-axis stepper arm with absolute encoders",
        description:
            "Five-axis arm driven by NEMA 17 steppers on TMC2209/TMC2208 drivers, " +
            "step mode set over UART. Axes 1-4 are geared 9:1; axis 5 is direct " +
            "drive. Every axis carries an MT6701 absolute encoder on its output: the " +
            "arm knows its true pose at power-up, and a hybrid controller uses the " +
            "encoders to correct the motors continuously while they move.",
        controller: "Arduino Uno R4 (or Uno Q)",
        driver: "TMC2209 + TMC2208 (STEP/DIR, UART step mode)",
        servoType: "NEMA 17 stepper",
        bus: "STEP/DIR + analog encoders",
        image: "",

        // Rig in content/view3d/rigs/, exported from dragon_arm_trailer.blend.
        view3d: "dragon-arm-one",

        // ---- Geometry (see Kinematics.js) -------------------------------
        // What the "move tool" blocks solve against. Every number comes from
        // the CAD, via the pivots in content/view3d/rigs/dragon-arm-one/rig.json:
        //   J2 pivot is 125 mm above the table, on the base axis
        //   J2 -> J3  (106.729, 226.079)  = 250 mm
        //   J3 -> J4  (138.674, 144.117)  = 200 mm
        //   J4 -> J5  ( 15.576,  79.488)  =  81 mm, and the claws' face is
        //             another 10 mm along the tool axis
        // The sideways offsets of the links cancel (-49 + 19 + 30 = 0), so the
        // tool point sits in the vertical plane through the base axis.
        // `cad` is rig.json's calibration block: the geometric angle of each
        // joint in the pose the CAD was built in, and which way the rig turns.
        kinematics: {
            type: "yawPitch3",
            yawJoint: "axis1",
            pitchJoints: ["axis2", "axis3", "axis4"],
            shoulderHeightMm: 125,
            upperArmMm: 250,
            forearmMm: 200,
            wristMm: 81,
            toolLengthMm: 10,
            // Height of the surface the base stands on. The validator warns
            // when the tool point goes below it.
            floorMm: 0,
            cad: {
                axis1: { deg: 0,         sign: 1  },
                axis2: { deg: 64.7287,   sign: -1 },
                axis3: { deg: -110.8313, sign: -1 },
                axis4: { deg: -32.7288,  sign: -1 }
            },
            moveAccent: "#A3E635"
        },

        // What kind of actuator this arm uses. Drives which code generator runs
        // and which hardware fields the configuration page shows.
        driveType: "stepper",

        // ---- Motor / driver configuration ------------------------------
        motorFullStepsPerRev: 200,

        // 1 = full step  ("strength"): half the step rate for the Uno to
        //                 produce, and the driver still interpolates to 256
        //                 microsteps internally, so motion stays smooth.
        // 2 = half step  ("precision"): twice the commanded resolution.
        // Selected over UART, because the TMC2208 MS pins cannot ask for
        // full step at all. MS1=5V/MS2=GND remains the power-up default.
        microsteps: MICROSTEPS,

        // EN is a shared, Arduino-driven net on the carrier board. Active low.
        enablePin: "A0",

        // ---- Driver UART ------------------------------------------------
        // One write-only line to every driver. They all share a slave address,
        // so a single datagram configures the whole board at once; nothing is
        // ever read back (the encoders cover that, and the Uno has no pins
        // spare). D0/D1 stay free for USB debugging.
        driverChip: "TMC2209 (axes 1-2) + TMC2208 (axes 3-5)",
        uartEnabled: true,
        uartTxPin: 12,
        uartRxPinDummy: 13,      // SoftwareSerial insists on an RX pin
        uartBaud: 115200,

        // The board carries two different chips on ONE shared TX line, and a
        // datagram only reaches the address it is stamped with:
        //   TMC2208 - address is fixed at 0, it does not accept any other
        //   TMC2209 - MS1/MS2 select it; 5V/GND makes it 1
        // So the configuration is sent once per address. Drivers ignore
        // datagrams addressed elsewhere, which is why this is safe and why
        // sending only one address silently leaves half the board unconfigured.
        uartSlaveAddresses: [0, 1],

        // ---- Encoders ---------------------------------------------------
        encoderType: "MT6701",
        // "analog": OUT is a voltage proportional to angle, read with
        // analogRead(). "pwm" would need pulseIn(), which blocks.
        encoderMode: "analog",
        encoderAdcCounts: 1024,          // Arduino Uno ADC is 10-bit
        encoderSamples: 8,               // averaged; one ADC count is ~0.35 deg
        // Read every encoder at boot to learn the true pose, and re-sync an
        // axis from its encoder each time one of its movements finishes.
        encoderReadAtStartup: true,
        encoderVerifyAfterMove: true,
        // Diagnostic build: stream encoder angles with the motors disabled and
        // run nothing else, so the encoders can be checked by hand.
        encoderMonitorMode: false,

        // ---- Startup ----------------------------------------------------
        // Direction probe: nudge each axis one way, watch the encoder, and
        // learn which DIR level increases the angle. Never runs towards a
        // limit -- the generated code picks the direction that has room.
        directionCalibration: true,
        calibrationProbeDeg: 5,
        calibrationStepIntervalUs: 1500,
        calibrationSettleMs: 150,

        startupHoming: false,
        startDelayMs: 1000,

        // ---- Motion -----------------------------------------------------
        minDuration: 0.05,
        maxDuration: 120.0,
        // Steppers want a genuine acceleration ramp, not a smoothstep.
        // Cosine S-curve: speed ramps along half a cosine, so acceleration
        // builds and fades smoothly instead of switching on and off.
        motionProfile: "scurve",
        defaultRampFraction: 0.25,
        // Not used by the stepper generator (kept so shared code that reads it
        // has a sane value).
        naturalSecondsPer60Deg: 0.17,
        holdRefreshMs: 0,
        releaseAfterSequence: false,

        joints: [
            stepperAxis({
                id: "axis1", name: "Axis-1", subtitle: "Base rotation",
                chip: "TMC2209",
                stepPin: 2, dirPin: 3, encoderPin: "A1",
                gearRatio: 9, min: -150, max: 150, home: 0,
                encoderOffset: 180, tolerance: 0.5,
                viewZero: 180, viewReversed: false,
                maxSpeed: 60, maxAccel: 120, accent: "#A78BFA"
            }),
            stepperAxis({
                id: "axis2", name: "Axis-2", subtitle: "Shoulder",
                chip: "TMC2209",
                stepPin: 4, dirPin: 5, encoderPin: "A2",
                gearRatio: 9, min: 0, max: 135, home: 50,
                encoderOffset: 0, tolerance: 0.5,
                viewZero: 70, viewReversed: false,
                maxSpeed: 60, maxAccel: 120, accent: "#7C9CF5"
            }),
            stepperAxis({
                id: "axis3", name: "Axis-3", subtitle: "Elbow",
                chip: "TMC2208",
                stepPin: 6, dirPin: 7, encoderPin: "A3",
                gearRatio: 9, min: 0, max: 240, home: 220,
                encoderOffset: 0, tolerance: 0.5,
                viewZero: 200.8, viewReversed: false,
                maxSpeed: 60, maxAccel: 120, accent: "#4FD1C5"
            }),
            stepperAxis({
                id: "axis4", name: "Axis-4", subtitle: "Wrist pitch",
                chip: "TMC2208",
                stepPin: 8, dirPin: 9, encoderPin: "A4",
                gearRatio: 9, min: 0, max: 180, home: 135,
                encoderOffset: 0, tolerance: 0.5,
                viewZero: 122.7, viewReversed: false,
                maxSpeed: 60, maxAccel: 120, accent: "#E9A14B"
            }),
            stepperAxis({
                id: "axis5", name: "Axis-5", subtitle: "Wrist roll (direct drive)",
                chip: "TMC2208",
                stepPin: 10, dirPin: 11, encoderPin: "A5",
                gearRatio: 1, min: 0, max: 360, home: 0,
                encoderOffset: 0, tolerance: 1.5, continuous: true,
                viewZero: 0, viewReversed: false,
                maxSpeed: 180, maxAccel: 360, accent: "#F472B6"
            })
        ],

        // No inter-axis rules yet. The constraint system is live either way, so
        // adding one later is an entry here plus a case in Validator.validate().
        constraints: []
    }
}

function allModels() {
    return [ dragonArmDemo(), dragonArmOne() ]
}

function modelById(id) {
    var models = allModels()
    for (var i = 0; i < models.length; ++i) {
        if (models[i].id === id)
            return models[i]
    }
    return models[0]
}

// Deep copy so callers can mutate a model without touching the catalogue.
function clone(model) {
    return JSON.parse(JSON.stringify(model))
}

function findJoint(model, jointId) {
    if (!model)
        return null
    for (var i = 0; i < model.joints.length; ++i) {
        if (model.joints[i].id === jointId)
            return model.joints[i]
    }
    return null
}

function gripperCommand(joint, commandId) {
    if (!joint || !joint.commands)
        return null
    for (var i = 0; i < joint.commands.length; ++i) {
        if (joint.commands[i].id === commandId)
            return joint.commands[i]
    }
    return joint.commands[0]
}
