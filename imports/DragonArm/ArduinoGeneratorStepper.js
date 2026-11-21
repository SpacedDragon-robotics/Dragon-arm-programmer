// ArduinoGeneratorStepper.js
//
// Emits an Arduino sketch for a STEP/DIR stepper arm with absolute encoders.
//
// How the generated controller works -- a HYBRID closed loop
//   * The step count is the fast, exact, noise-free position.
//   * The encoder is the truth about the ARM: it sees lost steps. It never
//     drives the motors directly; it slowly corrects a bias between the two,
//     above a deadband and below a speed cap.
//   * A 500 Hz control loop runs each motor at the plan's own S-curve speed
//     (feedforward) plus a correction for whatever error remains, under the
//     axis's speed and acceleration limits.
//   * Steps come from a phase accumulator, so any rate -- however slow -- is a
//     steady trickle of evenly spaced pulses, never stop-start bursts.
//   * Encoders are sampled one channel per loop pass, so no pass blocks for
//     longer than a single conversion.
//   * Only plain Arduino calls are used -- no timer or ADC registers -- so the
//     same sketch runs on an Uno R4 and an Uno Q (and an R3, more coarsely).
//   * Tool moves (straight lines of the tool) arrive as segments carrying a
//     `path`. Those rows follow a spline through MOVE_PATHS instead of a plain
//     from/to, with the spline's own slope as the feedforward speed. The
//     spline must stay identical to Kinematics.pathAngle()/pathSlope().

.pragma library
.import "RobotModels.js" as RobotModels
.import "PlanMath.js" as PlanMath

var CALIBRATION_MIN_PROBE_DEG = 2.0    // below this the ADC cannot see the move
var CALIBRATION_MIN_DETECT_DEG = 1.0

function axisEnum(joint) {
    return "AXIS_" + joint.id.toUpperCase().replace(/[^A-Z0-9]+/g, "_")
}

function f(value, decimals) {
    var d = decimals === undefined ? 1 : decimals
    return PlanMath.roundTo(value, d).toFixed(d)
}

function pad(text, width) {
    var s = String(text)
    while (s.length < width)
        s += " "
    return s
}

function padLeft(text, width) {
    var s = String(text)
    while (s.length < width)
        s = " " + s
    return s
}

// Analog pin names arrive as "A1"; emit them as the Arduino constant.
function pinLiteral(pin) {
    return String(pin)
}

// -------------------------------------------------------------------------
// Flatten the per-axis segments into one chronological move table
// -------------------------------------------------------------------------
function buildMoveTable(model, timeline) {
    var moves = []
    for (var jointId in timeline.segments) {
        var joint = RobotModels.findJoint(model, jointId)
        var segs = timeline.segments[jointId]
        for (var s = 0; s < segs.length; ++s) {
            var seg = segs[s]
            moves.push({
                axis: axisEnum(joint),
                axisName: joint.name,
                start: seg.start,
                end: seg.end,
                duration: seg.duration,
                from: seg.from,
                to: seg.to,
                ramp: seg.ramp,
                // Tool moves: the curve this axis follows (see Kinematics.js).
                path: seg.path ? seg.path : null,
                pathRow: -1
            })
        }
    }
    moves.sort(function (a, b) {
        if (Math.abs(a.start - b.start) > 1e-6)
            return a.start - b.start
        return a.axis < b.axis ? -1 : (a.axis > b.axis ? 1 : 0)
    })

    // Rows of the MOVE_PATHS table, in the order the moves run.
    var rows = 0
    for (var i = 0; i < moves.length; ++i) {
        if (moves[i].path)
            moves[i].pathRow = rows++
    }
    return moves
}

function buildHeader(model, timeline, moves) {
    var L = []
    L.push("/*")
    L.push(" * " + model.name + " – generated movement sequence")
    L.push(" * Produced by SpaceDragon Robot Programmer. Edits are overwritten on regenerate.")
    L.push(" *")
    L.push(" * Controller : " + model.controller)
    L.push(" * Drivers    : " + model.driver)
    L.push(" * Motors     : " + model.servoType + " × " + model.joints.length)
    L.push(" * Encoders   : " + model.encoderType + " absolute, "
           + model.encoderMode + " output")
    L.push(" * Sequence   : " + f(timeline.endTime, 3) + " s, after a "
           + Math.round(model.startDelayMs) + " ms start delay")
    L.push(" *")
    L.push(" * Microstep : " + microstepLabel(model.microsteps)
           + (model.uartEnabled ? ", set over UART at startup" : ""))
    L.push(" *")
    L.push(" * Only core libraries are used"
           + (model.uartEnabled ? " (SoftwareSerial for the driver UART)." : "."))
    L.push(" *")

    L.push(" * Axes")
    L.push(" * " + pad("axis", 9) + pad("driver", 10) + pad("STEP", 6) + pad("DIR", 6)
           + pad("enc", 5) + pad("gear", 7) + pad("steps/deg", 11)
           + pad("range", 18) + "max speed")
    for (var i = 0; i < model.joints.length; ++i) {
        var j = model.joints[i]
        L.push(" * " + pad(j.name, 9)
               + pad(j.driverChip ? j.driverChip : "-", 10)
               + pad("D" + j.stepPin, 6)
               + pad("D" + j.dirPin, 6)
               + pad(j.encoderPin, 5)
               + pad(f(j.gearRatio, 0) + ":1", 7)
               + pad(f(j.stepsPerDegree, 3), 11)
               + pad(f(j.mechMin, 0) + "° to " + f(j.mechMax, 0) + "°", 18)
               + f(j.maxSpeedDegPerSec, 0) + "°/s")
    }
    L.push(" *")

    if (moves.length === 0) {
        L.push(" * The timeline is empty. This sketch only calibrates and holds.")
    } else {
        L.push(" * Timeline")
        L.push(" * " + pad("start", 9) + pad("end", 9) + pad("axis", 10)
               + pad("from", 10) + pad("to", 10) + pad("duration", 11) + "ramp")
        for (i = 0; i < moves.length; ++i) {
            var m = moves[i]
            L.push(" * " + pad(f(m.start, 2) + " s", 9)
                   + pad(f(m.end, 2) + " s", 9)
                   + pad(m.axisName, 10)
                   + pad(f(m.from) + "°", 10)
                   + pad(f(m.to) + "°", 10)
                   + pad(f(m.duration, 2) + " s", 11)
                   + Math.round(m.ramp * 100) + "%")
        }
        L.push(" *")
        L.push(" * Rows that share a start time begin together; rows never block each other.")
    }
    L.push(" */")
    return L.join("\n")
}

// -------------------------------------------------------------------------
// Sections
// -------------------------------------------------------------------------
function buildConfigSection(model) {
    var L = []
    L.push("// ===========================================================================")
    L.push("// 1. Hardware configuration")
    L.push("//    Mirror of the Robot Model page. Change it there and regenerate, or")
    L.push("//    tweak these numbers while commissioning the arm.")
    L.push("// ===========================================================================")
    L.push("")
    L.push("static const uint16_t MOTOR_FULL_STEPS_PER_REV = " + model.motorFullStepsPerRev + ";")
    L.push("static const uint8_t  MICROSTEPS               = " + model.microsteps
           + ";      // TMC2208 hardware setting")
    L.push("")
    L.push("enum AxisId : uint8_t {")
    for (var i = 0; i < model.joints.length; ++i) {
        L.push("  " + pad(axisEnum(model.joints[i]) + ",", 16)
               + "// " + model.joints[i].name + " – " + model.joints[i].subtitle)
    }
    L.push("  AXIS_COUNT")
    L.push("};")
    L.push("")
    L.push("struct AxisConfig {")
    L.push("  uint8_t  stepPin;")
    L.push("  uint8_t  dirPin;")
    L.push("  uint8_t  encoderPin;             // MT6701 analog OUT")
    L.push("  float    stepsPerDegree;         // microsteps per degree of OUTPUT travel")
    L.push("  float    minAngleDeg;            // mechanical limits")
    L.push("  float    maxAngleDeg;")
    L.push("  float    encoderOffsetDeg;       // raw encoder degrees at program zero")
    L.push("  bool     encoderInverted;        // encoder counts against the axis")
    L.push("  bool     continuousRotation;     // angle wraps through 360")
    L.push("  float    deadbandDeg;            // encoder disagreement ignored below this")
    L.push("  float    maxSpeedDegPerSec;      // hard limits: a stepper pushed past")
    L.push("  float    maxAccelDegPerSec2;     //   them stalls and loses steps")
    L.push("  float    trackingGain;           // 1/s: how hard the motor chases the plan")
    L.push("  float    correctionGain;         // 1/s: how fast the encoder corrects the steps")
    L.push("  float    maxCorrectionDegPerSec; // cap on that correction")
    L.push("  float    encoderFilterMs;        // encoder low-pass time constant")
    L.push("};")
    L.push("")
    L.push("static const AxisConfig AXIS_CONFIG[AXIS_COUNT] = {")
    L.push("  //  STEP DIR enc  steps/deg   min       max      offset  inv    wraps")
    L.push("  //  deadband  speed   accel   track  enc.gain  max corr  filter")
    for (i = 0; i < model.joints.length; ++i) {
        var j = model.joints[i]
        L.push("  // " + j.name + " – " + j.subtitle)
        L.push("  { " + padLeft(pinLiteral(j.stepPin), 3) + ", "
               + padLeft(pinLiteral(j.dirPin), 2) + ", "
               + padLeft(pinLiteral(j.encoderPin), 3) + ", "
               + padLeft(f(j.stepsPerDegree, 4) + "f", 9) + ", "
               + padLeft(f(j.mechMin, 1) + "f", 8) + ", "
               + padLeft(f(j.mechMax, 1) + "f", 8) + ", "
               + padLeft(f(j.encoderOffsetDeg, 1) + "f", 7) + ", "
               + (j.encoderInverted ? "true " : "false") + ", "
               + (j.continuousRotation ? "true " : "false") + ",")
        L.push("    " + padLeft(f(j.toleranceDeg, 2) + "f", 6) + ", "
               + padLeft(f(j.maxSpeedDegPerSec, 1) + "f", 7) + ", "
               + padLeft(f(j.maxAccelDegPerSec2, 1) + "f", 7) + ", "
               + padLeft(f(j.trackingGain, 1) + "f", 5) + ", "
               + padLeft(f(j.correctionGain, 2) + "f", 6) + ", "
               + padLeft(f(j.maxCorrectionDegPerSec, 1) + "f", 6) + ", "
               + padLeft(f(j.encoderFilterMs, 1) + "f", 6) + " }"
               + (i < model.joints.length - 1 ? "," : ""))
    }
    L.push("};")
    L.push("")
    L.push("// ---- Encoders -------------------------------------------------------")
    L.push("#if defined(ARDUINO_ARCH_AVR)")
    L.push("static const uint8_t  ENCODER_ADC_BITS = 10;   // classic Uno: 0.35 deg per count")
    L.push("#else")
    L.push("static const uint8_t  ENCODER_ADC_BITS = 14;   // Uno R4 / Uno Q: 0.022 deg per count")
    L.push("#endif")
    L.push("static const uint32_t ENCODER_ADC_COUNTS  = 1UL << ENCODER_ADC_BITS;")
    L.push("static const uint8_t  ENCODER_SAMPLES     = " + model.encoderSamples
           + ";      // averaged; blocking reads at startup only")
    L.push("static const uint8_t  ENCODER_REPORT_READS = 6;   // used by the diagnostic")
    L.push("")
    L.push("// Set true to test the encoders and nothing else. The drivers are left")
    L.push("// DISABLED so every axis can be turned by hand, no probe runs, no sequence")
    L.push("// runs, and the readings stream forever. If an angle does not follow the")
    L.push("// axis as you turn it, the fault is in the encoder or its wiring, not in")
    L.push("// the motion code -- and nothing else in this sketch can work until it does.")
    L.push("static const bool     ENCODER_MONITOR = "
           + (model.encoderMonitorMode ? "true" : "false") + ";")
    L.push("static const uint16_t ENCODER_MONITOR_INTERVAL_MS = 250;")
    L.push("")
    L.push("// ---- Hybrid controller --------------------------------------------")
    L.push("// false = run the steppers open loop (encoders read at startup only).")
    L.push("static const bool     ENCODER_CORRECTION         = "
           + (model.encoderVerifyAfterMove ? "true" : "false") + ";")
    L.push("static const uint16_t CONTROL_PERIOD_US          = 2000;  // 500 Hz")
    L.push("// One encoder per sample, round-robin: every axis is read every")
    L.push("// AXIS_COUNT x this, without any pass blocking for more than one read.")
    L.push("static const uint16_t ENCODER_SAMPLE_INTERVAL_US = 400;")
    L.push("static const uint16_t DIR_CHECK_MS               = 400;")
    L.push("static const float    DIR_CHECK_MIN_DEG          = 5.0f;")
    L.push("static const float    STALL_WARN_DEG             = 5.0f;")
    L.push("")
    L.push("// ---- Startup direction probe ---------------------------------------")
    L.push("// Nudges each axis and watches its encoder to learn which DIR level")
    L.push("// increases the angle, so the wiring does not have to be guessed.")
    L.push("static const bool     DIRECTION_CALIBRATION        = "
           + (model.directionCalibration ? "true" : "false") + ";")
    L.push("static const float    CALIBRATION_PROBE_DEG        = "
           + f(model.calibrationProbeDeg, 1) + "f;")
    L.push("static const float    CALIBRATION_MIN_PROBE_DEG    = "
           + f(CALIBRATION_MIN_PROBE_DEG, 1) + "f;")
    L.push("static const float    CALIBRATION_MIN_DETECT_DEG   = "
           + f(CALIBRATION_MIN_DETECT_DEG, 1) + "f;")
    L.push("// The probe runs at max speed / CALIBRATION_SLOWDOWN, floored by")
    L.push("// CALIBRATION_STEP_INTERVAL_US, so it is always well inside the axis limit.")
    L.push("static const float    CALIBRATION_SLOWDOWN         = 4.0f;")
    L.push("static const uint16_t CALIBRATION_STEP_INTERVAL_US = "
           + Math.round(model.calibrationStepIntervalUs) + ";")
    L.push("static const uint16_t CALIBRATION_SETTLE_MS        = "
           + Math.round(model.calibrationSettleMs) + ";")
    L.push("")
    if (hasEnablePin(model)) {
        L.push("// Shared driver enable. Active low: LOW powers the motors.")
        L.push("static const uint8_t ENABLE_PIN = " + pinLiteral(model.enablePin) + ";")
    } else {
        L.push("// Every driver's EN pin is strapped to GND, so the outputs are always")
        L.push("// live and there is no enable line for the sketch to drive.")
    }

    if (model.uartEnabled) {
        L.push("")
        L.push("// ---- Driver UART ----------------------------------------------------")
        L.push("// Write-only, one line to every driver. They share a slave address, so a")
        L.push("// single datagram configures the whole board at once. Nothing is read")
        L.push("// back, so the RX pin is a dummy that SoftwareSerial merely requires.")
        L.push("static const uint8_t  UART_TX_PIN       = " + model.uartTxPin + ";")
        L.push("static const uint8_t  UART_RX_PIN_DUMMY = " + model.uartRxPinDummy + ";")
        L.push("static const uint32_t UART_BAUD         = " + model.uartBaud + "UL;")
        var addresses = model.uartSlaveAddresses
                ? model.uartSlaveAddresses
                : [model.uartSlaveAddress !== undefined ? model.uartSlaveAddress : 0]
        L.push("// Every driver family on the shared line needs its own datagram: a")
        L.push("// TMC2208 only ever answers to address 0, a TMC2209 to whatever MS1/MS2")
        L.push("// select. Addressing just one leaves the rest on their MS-pin default,")
        L.push("// which silently halves or doubles every movement on those axes.")
        L.push("static const uint8_t UART_ADDRESSES[] = { " + addresses.join(", ") + " };")
        L.push("static const uint8_t UART_ADDRESS_COUNT ="
               + " sizeof(UART_ADDRESSES) / sizeof(UART_ADDRESSES[0]);")
        L.push("")
        L.push("static const uint8_t REG_GCONF    = 0x00;")
        L.push("static const uint8_t REG_CHOPCONF = 0x6C;")
        L.push("")
        L.push("// GCONF, written whole because we cannot read it back first:")
        L.push("//   bit0 I_scale_analog  = 1  run current set by the VREF trimpot")
        L.push("//   bit6 pdn_disable     = 1  PDN_UART is a UART pin, not power-down")
        L.push("//   bit7 mstep_reg_select= 1  MRES comes from CHOPCONF, not MS1/MS2")
        L.push("//   bit8 multistep_filt  = 1  (reset default)")
        L.push("// Without bits 6 and 7 the MS pins keep control and the full-step")
        L.push("// request below is silently ignored.")
        L.push("static const uint32_t GCONF_VALUE = 0x000001C1UL;")
        L.push("")
        L.push("// CHOPCONF reset default with intpol = 1 (bit 28). Interpolation is why")
        L.push("// full step still moves smoothly: the driver fills in 256 microsteps")
        L.push("// internally, the Uno just sends a quarter as many pulses.")
        L.push("static const uint32_t CHOPCONF_BASE = 0x10000053UL;")
        L.push("// MRES field, bits 24-27. 8 = full step, 7 = half step.")
        L.push("static const uint8_t  CHOPCONF_MRES = " + mresFor(model.microsteps)
               + ";   // " + microstepLabel(model.microsteps))
    }
    return L.join("\n")
}

function hasEnablePin(model) {
    return model.enablePin !== undefined && model.enablePin !== null
            && String(model.enablePin) !== "-1" && String(model.enablePin) !== ""
}

// TMC MRES encoding: 0 = 256 microsteps, each step up halves it, 8 = full step.
function mresFor(microsteps) {
    switch (Math.round(microsteps)) {
    case 1:   return 8
    case 2:   return 7
    case 4:   return 6
    case 8:   return 5
    case 16:  return 4
    case 32:  return 3
    case 64:  return 2
    case 128: return 1
    default:  return 0
    }
}

function microstepLabel(microsteps) {
    return Math.round(microsteps) === 1 ? "full step" : "1/" + Math.round(microsteps) + " step"
}

function buildPlanSection(model, timeline, moves) {
    var L = []
    L.push("// ===========================================================================")
    L.push("// 2. Movement plan")
    L.push("//    One row per movement, in timeline order. Rows are independent: rows")
    L.push("//    sharing a startMs begin together, and rows on different axes simply")
    L.push("//    run at the same time.")
    L.push("// ===========================================================================")
    L.push("")
    L.push("struct AxisMove {")
    L.push("  uint8_t  axis;")
    L.push("  uint32_t startMs;        // relative to the start of the sequence")
    L.push("  uint32_t durationMs;")
    L.push("  float    fromAngleDeg;   // planned position when this move begins")
    L.push("  float    toAngleDeg;     // absolute target position")
    L.push("  float    ramp;           // share of the move spent accelerating")
    L.push("  int16_t  path;           // row of MOVE_PATHS to follow, -1 = straight from/to")
    L.push("};")
    L.push("")

    // ---- Tool-move paths ------------------------------------------------
    var pathMoves = []
    var i
    for (i = 0; i < moves.length; ++i) {
        if (moves[i].path)
            pathMoves.push(moves[i])
    }

    L.push("// Tool moves (\"move the tool up 50 mm\"). For the TOOL to travel in a")
    L.push("// straight line no axis can simply run from one angle to another: each")
    L.push("// has to follow its own curve. A row here is one axis's angle at")
    L.push("// PATH_POINTS evenly spaced points along the tool's line, solved by the")
    L.push("// app; pathAngle() joins them with a smooth spline. How fast the tool")
    L.push("// advances along the line is the move's ordinary ramp.")
    if (pathMoves.length === 0) {
        L.push("static const uint8_t PATH_POINTS = 2;")
        L.push("static const float MOVE_PATHS[1][PATH_POINTS] = {")
        L.push("  { 0.0f, 0.0f }   // placeholder: this plan has no tool moves")
        L.push("};")
    } else {
        var points = pathMoves[0].path.length
        L.push("static const uint8_t PATH_POINTS = " + points + ";")
        L.push("static const float MOVE_PATHS[][PATH_POINTS] = {")
        for (i = 0; i < pathMoves.length; ++i) {
            var pm = pathMoves[i]
            L.push("  // " + pm.pathRow + ": " + pm.axisName + ", t = " + f(pm.start, 3) + " s")
            var row = []
            for (var k = 0; k < pm.path.length; ++k)
                row.push(f(pm.path[k], 3) + "f")
            // Eight values per line keeps the table readable.
            var lines = []
            for (k = 0; k < row.length; k += 8)
                lines.push("    " + row.slice(k, k + 8).join(", "))
            L.push("  {")
            L.push(lines.join(",\n"))
            L.push("  }" + (i < pathMoves.length - 1 ? "," : ""))
        }
        L.push("};")
    }
    L.push("")

    if (moves.length === 0) {
        L.push("// The timeline is empty – this sketch commands no movement.")
        L.push("static const AxisMove MOVE_PLAN[1] = {")
        L.push("  { 0, 0, 0, 0.0f, 0.0f, 0.0f, -1 }   // placeholder, not executed")
        L.push("};")
        L.push("static const uint8_t MOVE_COUNT = 0;")
    } else {
        L.push("static const AxisMove MOVE_PLAN[] = {")
        for (i = 0; i < moves.length; ++i) {
            var m = moves[i]
            L.push("  // t = " + f(m.start, 3) + " s – " + m.axisName + " "
                   + f(m.from) + "° → " + f(m.to) + "° over "
                   + f(m.duration, 3) + " s, ramp " + Math.round(m.ramp * 100) + "%"
                   + (m.path ? ", along tool path " + m.pathRow : ""))
            L.push("  { " + pad(m.axis + ",", 14)
                   + padLeft(Math.round(m.start * 1000), 7) + ", "
                   + padLeft(Math.round(m.duration * 1000), 7) + ", "
                   + padLeft(f(m.from, 2) + "f", 10) + ", "
                   + padLeft(f(m.to, 2) + "f", 10) + ", "
                   + padLeft(f(m.ramp, 3) + "f", 7) + ", "
                   + padLeft(m.pathRow, 3) + " }"
                   + (i < moves.length - 1 ? "," : ""))
        }
        L.push("};")
        L.push("static const uint8_t MOVE_COUNT = sizeof(MOVE_PLAN) / sizeof(MOVE_PLAN[0]);")
    }

    L.push("static const uint32_t SEQUENCE_DURATION_MS   = "
           + Math.round(timeline.endTime * 1000) + "UL;")
    L.push("static const uint32_t START_DELAY_MS         = "
           + Math.round(model.startDelayMs) + "UL;")
    L.push("static const bool     REPEAT_SEQUENCE        = false;  // true loops forever")
    return L.join("\n")
}

function buildRuntimeSection(model) {
    var L = []
    L.push("// ===========================================================================")
    L.push("// 3. Runtime")
    L.push("// ===========================================================================")
    L.push("")
    L.push("static long     stepCount[AXIS_COUNT];         // motor position, exact, in steps")
    L.push("static float    stepPhase[AXIS_COUNT];         // fraction of a step still owed")
    L.push("static float    stepRate[AXIS_COUNT];          // commanded steps/s, signed")
    L.push("static float    axisSpeed[AXIS_COUNT];         // commanded deg/s after limits")
    L.push("static int8_t   dirLevelWritten[AXIS_COUNT];   // last DIR level written, -1 = none")
    L.push("static bool     dirHighIncreases[AXIS_COUNT];")
    L.push("static bool     stepPinRaised[AXIS_COUNT];")
    L.push("static float    encoderAngle[AXIS_COUNT];      // low-passed encoder angle, deg")
    L.push("static float    stepAngleFiltered[AXIS_COUNT]; // step angle through the SAME filter")
    L.push("static uint32_t encoderSampleUs[AXIS_COUNT];")
    L.push("static float    bias[AXIS_COUNT];              // encoder minus step count, deg")
    L.push("static float    holdAngle[AXIS_COUNT];         // pose held before the first move")
    L.push("static float    dirRefStepAngle[AXIS_COUNT];")
    L.push("static float    dirRefEncoder[AXIS_COUNT];")
    L.push("static uint32_t lastStallWarnMs[AXIS_COUNT];")
    L.push("static float    moveFromAngle[MOVE_COUNT > 0 ? MOVE_COUNT : 1];")
    L.push("static uint8_t  encoderCursor    = 0;")
    L.push("static uint32_t lastEncoderUs    = 0;")
    L.push("static uint32_t lastPassUs       = 0;")
    L.push("static uint32_t lastControlUs    = 0;")
    L.push("static uint32_t lastDirCheckMs   = 0;")
    L.push("static uint32_t bootMs           = 0;")
    L.push("static bool     sequenceFinished = false;")
    L.push("")
    L.push("// ---- Reporting ------------------------------------------------------")
    L.push("")
    L.push("// Print the axis by the name the app uses. The loop index is an")
    L.push("// implementation detail and reading \"Axis 2\" for Axis-3 is a trap.")
    L.push("void printAxisName(uint8_t axis) {")
    L.push("  switch (axis) {")
    for (var n = 0; n < model.joints.length; ++n) {
        L.push("  case " + axisEnum(model.joints[n]) + ": Serial.print(F(\""
               + model.joints[n].name + "\")); break;")
    }
    L.push("  default: Serial.print(F(\"Axis?\")); break;")
    L.push("  }")
    L.push("}")
    L.push("")
    L.push("// ---- Geometry -------------------------------------------------------")
    L.push("")
    L.push("long angleToSteps(uint8_t axis, float angleDeg) {")
    L.push("  return lround(angleDeg * AXIS_CONFIG[axis].stepsPerDegree);")
    L.push("}")
    L.push("")
    L.push("float stepsToAngle(uint8_t axis, long steps) {")
    L.push("  return (float)steps / AXIS_CONFIG[axis].stepsPerDegree;")
    L.push("}")
    L.push("")
    L.push("// Signed difference, taking the short way round for axes that wrap.")
    L.push("float angleError(float measured, float believed, bool wraps) {")
    L.push("  float d = measured - believed;")
    L.push("  if (wraps) {")
    L.push("    while (d >  180.0f) d -= 360.0f;")
    L.push("    while (d < -180.0f) d += 360.0f;")
    L.push("  }")
    L.push("  return d;")
    L.push("}")
    L.push("")
    var scurve = model.motionProfile === "scurve"
    L.push("// Shape of a movement between 0 and 1: accelerate for `ramp` of the")
    L.push("// travel, coast, then decelerate. This is the identical curve the app")
    L.push("// used to validate the plan -- change one, change the other.")
    if (scurve) {
        L.push("//")
        L.push("// S-curve: speed rises along half a cosine, so acceleration builds from")
        L.push("// zero and fades back to zero. No step change in force at either end of")
        L.push("// the ramp, which is what makes a straight-line ramp feel jerky.")
    }
    L.push("float shapeProgress(float progress, float ramp) {")
    L.push("  if (progress <= 0.0f) return 0.0f;")
    L.push("  if (progress >= 1.0f) return 1.0f;")
    L.push("  if (ramp <= 0.0f)     return progress;")
    L.push("  if (ramp > 0.5f)      ramp = 0.5f;")
    L.push("")
    L.push("  const float peak = 1.0f / (1.0f - ramp);   // area under the curve is 1")
    if (scurve) {
        L.push("  const float k = ramp / (2.0f * (float)M_PI);")
        L.push("  if (progress < ramp) {")
        L.push("    return peak * (progress * 0.5f - k * sin((float)M_PI * progress / ramp));")
        L.push("  }")
        L.push("  if (progress <= 1.0f - ramp) {")
        L.push("    return peak * (ramp * 0.5f + (progress - ramp));")
        L.push("  }")
        L.push("  const float remaining = 1.0f - progress;")
        L.push("  return 1.0f - peak * (remaining * 0.5f")
        L.push("                        - k * sin((float)M_PI * remaining / ramp));")
    } else {
        L.push("  if (progress < ramp) {")
        L.push("    return peak * progress * progress / (2.0f * ramp);")
        L.push("  }")
        L.push("  if (progress <= 1.0f - ramp) {")
        L.push("    return peak * (ramp * 0.5f + (progress - ramp));")
        L.push("  }")
        L.push("  const float remaining = 1.0f - progress;")
        L.push("  return 1.0f - peak * remaining * remaining / (2.0f * ramp);")
    }
    L.push("}")
    L.push("")
    L.push("// Normalised SPEED of the same curve: d(shapeProgress)/d(progress). The")
    L.push("// controller feeds this forward, so each motor runs at the plan's own speed")
    L.push("// instead of waiting for a position error to build up first.")
    L.push("float shapeVelocity(float progress, float ramp) {")
    L.push("  if (progress <= 0.0f || progress >= 1.0f) return 0.0f;")
    L.push("  if (ramp <= 0.0f) return 1.0f;")
    L.push("  if (ramp > 0.5f)  ramp = 0.5f;")
    L.push("")
    L.push("  const float peak = 1.0f / (1.0f - ramp);")
    L.push("  float edge = -1.0f;                       // distance into a ramp")
    L.push("  if (progress < ramp)             edge = progress;")
    L.push("  else if (progress > 1.0f - ramp) edge = 1.0f - progress;")
    L.push("  if (edge < 0.0f) return peak;             // cruising")
    if (scurve)
        L.push("  return peak * (1.0f - cos((float)M_PI * edge / ramp)) * 0.5f;")
    else
        L.push("  return peak * edge / ramp;")
    L.push("}")
    L.push("")
    L.push("// ---- Tool-move paths ------------------------------------------------")
    L.push("//")
    L.push("// Catmull-Rom spline through one row of MOVE_PATHS. `along` is how far")
    L.push("// along the tool's line the move is, 0..1. The spline keeps the angle AND")
    L.push("// its speed continuous from one stored point to the next, so the")
    L.push("// feedforward speed never steps. The app validated the plan on the")
    L.push("// identical spline (Kinematics.js) -- change one, change the other.")
    L.push("//")
    L.push("// Cubic between points i and i+1: ((a*t + b)*t + c)*t + d, t = 0..1. The")
    L.push("// neighbours beyond either end are mirrored.")
    L.push("void pathCubic(int16_t row, float along,")
    L.push("               float &t, float &a, float &b, float &c, float &d) {")
    L.push("  const float *p = MOVE_PATHS[row];")
    L.push("  const uint8_t last = PATH_POINTS - 1;")
    L.push("  if (along < 0.0f) along = 0.0f;")
    L.push("  if (along > 1.0f) along = 1.0f;")
    L.push("")
    L.push("  const float x = along * (float)last;")
    L.push("  uint8_t i = (uint8_t)x;")
    L.push("  if (i > last - 1) i = last - 1;")
    L.push("")
    L.push("  const float p1 = p[i];")
    L.push("  const float p2 = p[i + 1];")
    L.push("  const float p0 = (i > 0)         ? p[i - 1] : 2.0f * p1 - p2;")
    L.push("  const float p3 = (i + 2 <= last) ? p[i + 2] : 2.0f * p2 - p1;")
    L.push("")
    L.push("  t = x - (float)i;")
    L.push("  a = -0.5f * p0 + 1.5f * p1 - 1.5f * p2 + 0.5f * p3;")
    L.push("  b = p0 - 2.5f * p1 + 2.0f * p2 - 0.5f * p3;")
    L.push("  c = -0.5f * p0 + 0.5f * p2;")
    L.push("  d = p1;")
    L.push("}")
    L.push("")
    L.push("// Angle of the axis at this point of the line, degrees.")
    L.push("float pathAngle(int16_t row, float along) {")
    L.push("  float t, a, b, c, d;")
    L.push("  pathCubic(row, along, t, a, b, c, d);")
    L.push("  return ((a * t + b) * t + c) * t + d;")
    L.push("}")
    L.push("")
    L.push("// How fast that angle changes: degrees per whole line.")
    L.push("float pathSlope(int16_t row, float along) {")
    L.push("  float t, a, b, c, d;")
    L.push("  pathCubic(row, along, t, a, b, c, d);")
    L.push("  return ((3.0f * a * t + 2.0f * b) * t + c) * (float)(PATH_POINTS - 1);")
    L.push("}")
    L.push("")
    L.push("// ---- Encoders -------------------------------------------------------")
    L.push("")
    L.push("// Absolute angle of one axis, in the same coordinates the plan uses.")
    L.push("// analogRead() blocks for roughly 100 us per sample, so this is only")
    L.push("// ever called while the axis in question is standing still.")
    L.push("// Average ADC counts for one encoder, discarding the first reading.")
    L.push("// The ADC multiplexer needs time to settle after switching channels, and")
    L.push("// the sample taken immediately after the switch is unreliable with a")
    L.push("// higher-impedance source like the MT6701's analog output.")
    L.push("float readEncoderCounts(uint8_t axis) {")
    L.push("  const uint8_t pin = AXIS_CONFIG[axis].encoderPin;")
    L.push("  (void)analogRead(pin);            // settle the mux, discard")
    L.push("")
    L.push("  uint32_t sum = 0;")
    L.push("  for (uint8_t i = 0; i < ENCODER_SAMPLES; i++) {")
    L.push("    sum += analogRead(pin);")
    L.push("  }")
    L.push("  return (float)sum / ENCODER_SAMPLES;")
    L.push("}")
    L.push("")
    L.push("// Raw encoder angle, 0..360, before this axis's offset is applied.")
    L.push("float readEncoderRawDeg(uint8_t axis) {")
    L.push("  return readEncoderCounts(axis)")
    L.push("       * (360.0f / (float)(ENCODER_ADC_COUNTS - 1));")
    L.push("}")
    L.push("")
    L.push("// Raw 0..360 reading -> this axis's program angle. Kept separate so the")
    L.push("// diagnostic below can report the angle for the SAME samples it printed,")
    L.push("// instead of taking a second reading that may differ.")
    L.push("float encoderRawToAngle(uint8_t axis, float raw) {")
    L.push("  const AxisConfig &cfg = AXIS_CONFIG[axis];")
    L.push("  if (cfg.encoderInverted) raw = 360.0f - raw;")
    L.push("  float angle = raw - cfg.encoderOffsetDeg;")
    L.push("")
    L.push("  // Fold the reading into this axis's own range. Axis-1's encoder seam")
    L.push("  // sits opposite the arm's centre, which is what the offset is for.")
    L.push("  while (angle < cfg.minAngleDeg - 180.0f) angle += 360.0f;")
    L.push("  while (angle > cfg.maxAngleDeg + 180.0f) angle -= 360.0f;")
    L.push("  return angle;")
    L.push("}")
    L.push("")
    L.push("float readEncoderDeg(uint8_t axis) {")
    L.push("  return encoderRawToAngle(axis, readEncoderRawDeg(axis));")
    L.push("}")
    L.push("")
    L.push("// Diagnostic dump. If the arm travels by the right AMOUNT but ends up at")
    L.push("// the wrong absolute position, the cause is almost always here: either the")
    L.push("// counts are not changing (encoder unwired, or its OUT pin is in PWM mode")
    L.push("// rather than analog), or the offset is wrong.")
    L.push("//")
    L.push("// To calibrate: park an axis at a pose you can measure, read 'raw' below,")
    L.push("// and set that axis's Enc. offset to (raw - the angle it should report).")
    L.push("// `jitter` is the spread across several back-to-back reads of a motionless")
    L.push("// axis. It must be comfortably below CALIBRATION_MIN_DETECT_DEG, or the")
    L.push("// direction probe cannot tell a real nudge from noise and will report")
    L.push("// every axis as inconclusive. A large jitter means the OUT pin is in PWM")
    L.push("// mode rather than analog, or the signal is unshielded next to the motor")
    L.push("// cables, or ENCODER_SAMPLES is too low.")
    L.push("void reportEncoders() {")
    L.push("  for (uint8_t a = 0; a < AXIS_COUNT; a++) {")
    L.push("    float lo = 99999.0f, hi = -99999.0f, total = 0.0f;")
    L.push("    for (uint8_t k = 0; k < ENCODER_REPORT_READS; k++) {")
    L.push("      const float c = readEncoderCounts(a);")
    L.push("      if (c < lo) lo = c;")
    L.push("      if (c > hi) hi = c;")
    L.push("      total += c;")
    L.push("    }")
    L.push("    const float perCount = 360.0f / (float)(ENCODER_ADC_COUNTS - 1);")
    L.push("    const float counts   = total / ENCODER_REPORT_READS;")
    L.push("    const float raw      = counts * perCount;")
    L.push("")
    L.push("    Serial.print(F(\"  \")); printAxisName(a);")
    L.push("    Serial.print(F(\"  counts \")); Serial.print(counts, 1);")
    L.push("    Serial.print(F(\"  raw \"));    Serial.print(raw, 2);")
    L.push("    Serial.print(F(\"  jitter \"));Serial.print((hi - lo) * perCount, 2);")
    L.push("    Serial.print(F(\"  offset \")); Serial.print(AXIS_CONFIG[a].encoderOffsetDeg, 1);")
    L.push("    // Same samples as the raw figure above, so these can never disagree.")
    L.push("    Serial.print(F(\"  -> \"));     Serial.print(encoderRawToAngle(a, raw), 2);")
    L.push("    Serial.println(F(\" deg\"));")
    L.push("  }")
    L.push("}")
    L.push("")
    L.push("// ---- Encoders in the background ------------------------------------")
    L.push("//")
    L.push("// One encoder per call, round-robin, so a pass never blocks for more than")
    L.push("// a single conversion. The step angle goes through the SAME low-pass at the")
    L.push("// same instant: comparing a lagging encoder against an unfiltered step")
    L.push("// count would read the filter's own delay as an error, and drag the arm")
    L.push("// around at the end of every fast move.")
    L.push("void sampleNextEncoder(uint32_t nowUs) {")
    L.push("  if ((uint32_t)(nowUs - lastEncoderUs) < ENCODER_SAMPLE_INTERVAL_US) return;")
    L.push("  lastEncoderUs = nowUs;")
    L.push("")
    L.push("  const uint8_t a = encoderCursor;")
    L.push("  encoderCursor = (uint8_t)((encoderCursor + 1) % AXIS_COUNT);")
    L.push("  const AxisConfig &cfg = AXIS_CONFIG[a];")
    L.push("")
    L.push("  (void)analogRead(cfg.encoderPin);           // settle the mux, discard")
    L.push("  const float raw = (float)analogRead(cfg.encoderPin)")
    L.push("                  * (360.0f / (float)(ENCODER_ADC_COUNTS - 1));")
    L.push("  const float measured = encoderRawToAngle(a, raw);")
    L.push("")
    L.push("  const float dtMs  = (float)(uint32_t)(nowUs - encoderSampleUs[a]) * 0.001f;")
    L.push("  encoderSampleUs[a] = nowUs;")
    L.push("  const float alpha = dtMs / (cfg.encoderFilterMs + dtMs);")
    L.push("")
    L.push("  encoderAngle[a] += alpha * angleError(measured, encoderAngle[a],")
    L.push("                                       cfg.continuousRotation);")
    L.push("  stepAngleFiltered[a] += alpha * (stepsToAngle(a, stepCount[a])")
    L.push("                                   - stepAngleFiltered[a]);")
    L.push("}")
    L.push("")
    L.push("// ---- Stepping -------------------------------------------------------")
    L.push("")
    L.push("// Pulses are dropped at the START of the next pass, which shapes the")
    L.push("// pulse without a single busy-wait.")
    L.push("void lowerStepPins() {")
    L.push("  for (uint8_t a = 0; a < AXIS_COUNT; a++) {")
    L.push("    if (stepPinRaised[a]) {")
    L.push("      digitalWrite(AXIS_CONFIG[a].stepPin, LOW);")
    L.push("      stepPinRaised[a] = false;")
    L.push("    }")
    L.push("  }")
    L.push("}")
    L.push("")
    L.push("void stepOnce(uint8_t axis, int8_t direction) {")
    L.push("  const AxisConfig &cfg = AXIS_CONFIG[axis];")
    L.push("  const uint8_t level = ((direction > 0) == dirHighIncreases[axis]) ? HIGH : LOW;")
    L.push("  if (dirLevelWritten[axis] != (int8_t)level) {")
    L.push("    digitalWrite(cfg.dirPin, level);        // only when it changes")
    L.push("    dirLevelWritten[axis] = (int8_t)level;")
    L.push("  }")
    L.push("  digitalWrite(cfg.stepPin, HIGH);")
    L.push("  stepPinRaised[axis] = true;")
    L.push("  stepCount[axis]    += direction;")
    L.push("}")
    L.push("")
    L.push("// Emit evenly spaced steps at each axis's commanded rate. stepPhase holds")
    L.push("// the fraction of a step still owed, so a slow rate comes out as a steady")
    L.push("// trickle of pulses instead of stop-start bursts.")
    L.push("void serviceSteppers(float dt) {")
    L.push("  for (uint8_t a = 0; a < AXIS_COUNT; a++) {")
    L.push("    stepPhase[a] += stepRate[a] * dt;")
    L.push("    // A long pass must not build a backlog that then fires as a burst.")
    L.push("    if (stepPhase[a] >  2.0f) stepPhase[a] =  2.0f;")
    L.push("    if (stepPhase[a] < -2.0f) stepPhase[a] = -2.0f;")
    L.push("")
    L.push("    if (stepPhase[a] >= 1.0f) {")
    L.push("      stepPhase[a] -= 1.0f;")
    L.push("      stepOnce(a, 1);")
    L.push("    } else if (stepPhase[a] <= -1.0f) {")
    L.push("      stepPhase[a] += 1.0f;")
    L.push("      stepOnce(a, -1);")
    L.push("    }")
    L.push("  }")
    L.push("}")
    L.push("")
    L.push("// ---- Plan -----------------------------------------------------------")
    L.push("")
    L.push("// Where the plan wants an axis right now, and how fast it is moving there.")
    L.push("// Returns false while no movement for this axis has started yet.")
    L.push("bool planFor(uint8_t axis, uint32_t elapsedMs, float &angle, float &speed) {")
    L.push("  bool active = false;")
    L.push("  for (uint8_t i = 0; i < MOVE_COUNT; i++) {")
    L.push("    const AxisMove &move = MOVE_PLAN[i];")
    L.push("    if (move.axis != axis || elapsedMs < move.startMs) continue;")
    L.push("")
    L.push("    const float from   = moveFromAngle[i];")
    L.push("    const float travel = move.toAngleDeg - from;")
    L.push("    float progress = 1.0f;")
    L.push("    float rate     = 0.0f;                 // shaped progress per second")
    L.push("    if (move.durationMs > 0) {")
    L.push("      const uint32_t movingMs = elapsedMs - move.startMs;")
    L.push("      if (movingMs < move.durationMs) {")
    L.push("        progress = (float)movingMs / (float)move.durationMs;")
    L.push("        rate = shapeVelocity(progress, move.ramp) * 1000.0f / (float)move.durationMs;")
    L.push("      }")
    L.push("    }")
    L.push("")
    L.push("    // Later rows for the same axis overwrite earlier ones.")
    L.push("    const float shaped = shapeProgress(progress, move.ramp);")
    L.push("    if (move.path >= 0) {")
    L.push("      // Tool move: follow this axis's own curve, so the tool stays on its")
    L.push("      // line. `lead` is how far the arm really was from the planned start")
    L.push("      // (first move of an axis only, see rebaseFirstMoves). It fades out")
    L.push("      // along the move, which still ends exactly on the planned angle.")
    L.push("      const float lead = from - move.fromAngleDeg;")
    L.push("      angle = pathAngle(move.path, shaped) + lead * (1.0f - shaped);")
    L.push("      speed = (pathSlope(move.path, shaped) - lead) * rate;")
    L.push("    } else {")
    L.push("      angle = from + travel * shaped;")
    L.push("      speed = travel * rate;")
    L.push("    }")
    L.push("    active = true;")
    L.push("  }")
    L.push("  return active;")
    L.push("}")
    L.push("")
    L.push("// The first movement on each axis starts from where the arm ACTUALLY is,")
    L.push("// not from the pose the plan assumed, so nothing lurches when it starts.")
    L.push("void rebaseFirstMoves() {")
    L.push("  for (uint8_t i = 0; i < MOVE_COUNT; i++) {")
    L.push("    moveFromAngle[i] = MOVE_PLAN[i].fromAngleDeg;")
    L.push("  }")
    L.push("  for (uint8_t a = 0; a < AXIS_COUNT; a++) {")
    L.push("    for (uint8_t i = 0; i < MOVE_COUNT; i++) {")
    L.push("      if (MOVE_PLAN[i].axis != a) continue;")
    L.push("      moveFromAngle[i] = stepsToAngle(a, stepCount[a]) + bias[a];")
    L.push("      break;                                // only the first move")
    L.push("    }")
    L.push("  }")
    L.push("}")
    L.push("")
    L.push("// ---- Hybrid controller ----------------------------------------------")
    L.push("//")
    L.push("// The step count is the fast, exact position: no noise. The encoder is")
    L.push("// the truth about the ARM: it sees lost steps. So the encoder never")
    L.push("// drives the motors directly -- it slowly corrects a bias between the")
    L.push("// two, above a deadband and below a speed cap -- and the motors follow")
    L.push("// the plan using that corrected estimate. Each motor runs at the plan's")
    L.push("// own S-curve speed (feedforward) plus a small correction for whatever")
    L.push("// error is left.")
    L.push("void controlTick(bool running, uint32_t elapsedMs, float dt) {")
    L.push("  const uint32_t nowMs = millis();")
    L.push("")
    L.push("  for (uint8_t a = 0; a < AXIS_COUNT; a++) {")
    L.push("    const AxisConfig &cfg = AXIS_CONFIG[a];")
    L.push("")
    L.push("    // 1. What the plan wants. Before its first move an axis holds its")
    L.push("    //    power-up pose exactly, unclamped: clamping a hold would turn a")
    L.push("    //    mechanical limit into a destination.")
    L.push("    float desired      = holdAngle[a];")
    L.push("    float desiredSpeed = 0.0f;")
    L.push("    if (running && planFor(a, elapsedMs, desired, desiredSpeed)) {")
    L.push("      if (!cfg.continuousRotation) {")
    L.push("        if (desired < cfg.minAngleDeg) desired = cfg.minAngleDeg;")
    L.push("        if (desired > cfg.maxAngleDeg) desired = cfg.maxAngleDeg;")
    L.push("      }")
    L.push("    }")
    L.push("")
    L.push("    // 2. Encoder: nudge the bias towards what the arm really did. Inside")
    L.push("    //    the deadband nothing happens, so noise and backlash never move")
    L.push("    //    a motor; outside it the correction is a capped, smooth slide.")
    L.push("    const float disagreement = angleError(encoderAngle[a],")
    L.push("                                          stepAngleFiltered[a] + bias[a],")
    L.push("                                          cfg.continuousRotation);")
    L.push("    if (ENCODER_CORRECTION && fabs(disagreement) > cfg.deadbandDeg) {")
    L.push("      float correction = cfg.correctionGain * disagreement * dt;")
    L.push("      const float cap  = cfg.maxCorrectionDegPerSec * dt;")
    L.push("      if (correction >  cap) correction =  cap;")
    L.push("      if (correction < -cap) correction = -cap;")
    L.push("      bias[a] += correction;")
    L.push("    }")
    L.push("    if (fabs(disagreement) > STALL_WARN_DEG")
    L.push("        && (uint32_t)(nowMs - lastStallWarnMs[a]) > 2000UL) {")
    L.push("      lastStallWarnMs[a] = nowMs;")
    L.push("      printAxisName(a);")
    L.push("      Serial.print(F(\": encoder and motor disagree by \"));")
    L.push("      Serial.print(disagreement, 1);")
    L.push("      Serial.println(F(\" deg - stalling or slipping?\"));")
    L.push("    }")
    L.push("")
    L.push("    // 3. Follow the plan from the corrected estimate.")
    L.push("    const float estimate = stepsToAngle(a, stepCount[a]) + bias[a];")
    L.push("    const float error    = desired - estimate;")
    L.push("")
    L.push("    // The correction term is never faster than the axis could still stop")
    L.push("    // from, within the remaining error -- that is what prevents overshoot.")
    L.push("    float correction = cfg.trackingGain * error;")
    L.push("    const float stopSpeed = sqrt(2.0f * cfg.maxAccelDegPerSec2 * fabs(error));")
    L.push("    if (correction >  stopSpeed) correction =  stopSpeed;")
    L.push("    if (correction < -stopSpeed) correction = -stopSpeed;")
    L.push("")
    L.push("    float speed = desiredSpeed + correction;")
    L.push("")
    L.push("    // Standing still and within half a step of the target: do nothing,")
    L.push("    // rather than dither one step back and forth.")
    L.push("    if (desiredSpeed == 0.0f && fabs(error) < 0.5f / cfg.stepsPerDegree) {")
    L.push("      speed = 0.0f;")
    L.push("    }")
    L.push("")
    L.push("    // 4. Hard limits -- the same ones the plan was validated against.")
    L.push("    if (speed >  cfg.maxSpeedDegPerSec) speed =  cfg.maxSpeedDegPerSec;")
    L.push("    if (speed < -cfg.maxSpeedDegPerSec) speed = -cfg.maxSpeedDegPerSec;")
    L.push("    const float maxChange = cfg.maxAccelDegPerSec2 * dt;")
    L.push("    if (speed > axisSpeed[a] + maxChange) speed = axisSpeed[a] + maxChange;")
    L.push("    if (speed < axisSpeed[a] - maxChange) speed = axisSpeed[a] - maxChange;")
    L.push("")
    L.push("    axisSpeed[a] = speed;")
    L.push("    stepRate[a]  = speed * cfg.stepsPerDegree;")
    L.push("  }")
    L.push("}")
    L.push("")
    L.push("// ---- Direction sanity check -----------------------------------------")
    L.push("//")
    L.push("// If the startup probe was inconclusive, DIR is only a guess, and a wrong")
    L.push("// guess sends every movement the wrong way. Compare how far the motor was")
    L.push("// stepped with how far the arm actually went; opposite signs mean DIR is")
    L.push("// backwards. Flip it and re-anchor the step count on the encoder.")
    L.push("void checkDirections() {")
    L.push("  for (uint8_t a = 0; a < AXIS_COUNT; a++) {")
    L.push("    const AxisConfig &cfg = AXIS_CONFIG[a];")
    L.push("    const float commanded = stepAngleFiltered[a] - dirRefStepAngle[a];")
    L.push("    const float actual    = angleError(encoderAngle[a], dirRefEncoder[a],")
    L.push("                                       cfg.continuousRotation);")
    L.push("")
    L.push("    if (fabs(commanded) > DIR_CHECK_MIN_DEG")
    L.push("        && fabs(actual) > 1.0f + 2.0f * cfg.deadbandDeg")
    L.push("        && commanded * actual < 0.0f) {")
    L.push("      dirHighIncreases[a]  = !dirHighIncreases[a];")
    L.push("      dirLevelWritten[a]   = -1;              // force a DIR write")
    L.push("      stepCount[a]         = angleToSteps(a, encoderAngle[a]);")
    L.push("      stepAngleFiltered[a] = stepsToAngle(a, stepCount[a]);")
    L.push("      bias[a]      = 0.0f;")
    L.push("      axisSpeed[a] = 0.0f;")
    L.push("      stepPhase[a] = 0.0f;")
    L.push("      printAxisName(a);")
    L.push("      Serial.println(F(\": moved opposite to command - DIR corrected\"));")
    L.push("    }")
    L.push("")
    L.push("    dirRefStepAngle[a] = stepAngleFiltered[a];")
    L.push("    dirRefEncoder[a]   = encoderAngle[a];")
    L.push("  }")
    L.push("}")
    return L.join("\n")
}

function buildUartSection(model) {
    if (!model.uartEnabled)
        return ""

    var L = []
    L.push("")
    L.push("// ===========================================================================")
    L.push("// 4. Driver configuration over UART")
    L.push("//")
    L.push("//    The TMC2208's MS pins cannot select full step at all, so microstepping")
    L.push("//    is set here instead. This MUST run before the direction probe: the")
    L.push("//    probe steps blind and measures the result with the encoder, so it has")
    L.push("//    to know how far one step actually goes. A driver still sitting at its")
    L.push("//    power-up resolution would move a fraction of the expected amount and")
    L.push("//    the probe would report every axis as inconclusive.")
    L.push("// ===========================================================================")
    L.push("")
    L.push("#include <SoftwareSerial.h>")
    L.push("")
    L.push("static SoftwareSerial driverUart(UART_RX_PIN_DUMMY, UART_TX_PIN);")
    L.push("")
    L.push("// TMC UART datagram CRC: polynomial x^8 + x^2 + x + 1, MSB first.")
    L.push("uint8_t tmcCrc(const uint8_t *data, uint8_t length) {")
    L.push("  uint8_t crc = 0;")
    L.push("  for (uint8_t i = 0; i < length; i++) {")
    L.push("    uint8_t currentByte = data[i];")
    L.push("    for (uint8_t bit = 0; bit < 8; bit++) {")
    L.push("      if ((crc >> 7) ^ (currentByte & 0x01)) {")
    L.push("        crc = (uint8_t)((crc << 1) ^ 0x07);")
    L.push("      } else {")
    L.push("        crc = (uint8_t)(crc << 1);")
    L.push("      }")
    L.push("      currentByte >>= 1;")
    L.push("    }")
    L.push("  }")
    L.push("  return crc;")
    L.push("}")
    L.push("")
    L.push("void tmcWrite(uint8_t slaveAddress, uint8_t reg, uint32_t value) {")
    L.push("  uint8_t frame[8];")
    L.push("  frame[0] = 0x05;                        // sync")
    L.push("  frame[1] = slaveAddress;")
    L.push("  frame[2] = (uint8_t)(reg | 0x80);       // high bit marks a write")
    L.push("  frame[3] = (uint8_t)(value >> 24);")
    L.push("  frame[4] = (uint8_t)(value >> 16);")
    L.push("  frame[5] = (uint8_t)(value >> 8);")
    L.push("  frame[6] = (uint8_t)(value);")
    L.push("  frame[7] = tmcCrc(frame, 7);")
    L.push("")
    L.push("  for (uint8_t i = 0; i < 8; i++) {")
    L.push("    driverUart.write(frame[i]);")
    L.push("  }")
    L.push("  delay(2);                               // let the drivers latch it")
    L.push("}")
    L.push("")
    L.push("void configureDrivers() {")
    L.push("  driverUart.begin(UART_BAUD);")
    L.push("  delay(10);")
    L.push("")
    L.push("  const uint32_t chopconf = CHOPCONF_BASE | ((uint32_t)CHOPCONF_MRES << 24);")
    L.push("")
    L.push("  for (uint8_t i = 0; i < UART_ADDRESS_COUNT; i++) {")
    L.push("    const uint8_t address = UART_ADDRESSES[i];")
    L.push("    // Hand microstep control to the register, then set the resolution.")
    L.push("    tmcWrite(address, REG_GCONF, GCONF_VALUE);")
    L.push("    tmcWrite(address, REG_CHOPCONF, chopconf);")
    L.push("")
    L.push("    Serial.print(F(\"  driver address \")); Serial.print(address);")
    L.push("    Serial.println(F(\" configured\"));")
    L.push("  }")
    L.push("")
    L.push("  Serial.print(F(\"Step mode: \"));")
    L.push("  Serial.print(MICROSTEPS);")
    L.push("  Serial.println(F(\" microstep(s) per full step\"));")
    L.push("}")
    return L.join("\n")
}

function buildCalibrationSection() {
    var L = []
    L.push("")
    L.push("// ===========================================================================")
    L.push("// 5. Startup direction probe")
    L.push("//")
    L.push("//    Which DIR level increases an axis's angle depends on how the motor and")
    L.push("//    the encoder happen to be wired and mounted. Rather than guess, nudge")
    L.push("//    each axis and watch its encoder.")
    L.push("//")
    L.push("//    SAFETY: the probe direction is unknown by definition, so the nudge is")
    L.push("//    sized to fit inside the axis's remaining travel in BOTH directions. An")
    L.push("//    axis parked too close to a limit is skipped rather than risked.")
    L.push("//")
    L.push("//    This runs once, before any timeline motion, and is the only place in")
    L.push("//    the sketch that blocks.")
    L.push("// ===========================================================================")
    L.push("")
    L.push("void pulseBlind(uint8_t axis, uint8_t dirLevel, long steps) {")
    L.push("  const AxisConfig &cfg = AXIS_CONFIG[axis];")
    L.push("")
    L.push("  // Probe well below the axis's own ceiling. A fixed interval cannot work")
    L.push("  // here: the same microseconds are a gentle crawl on a 9:1 geared axis")
    L.push("  // and several times the stall speed on a direct-drive one. Starting a")
    L.push("  // stepper at full rate from rest just makes it buzz in place, which")
    L.push("  // reads back as \"the encoder saw nothing\".")
    L.push("  uint32_t intervalUs =")
    L.push("      (uint32_t)(1000000.0f / (cfg.maxSpeedDegPerSec * cfg.stepsPerDegree")
    L.push("                               / CALIBRATION_SLOWDOWN));")
    L.push("  if (intervalUs < CALIBRATION_STEP_INTERVAL_US) {")
    L.push("    intervalUs = CALIBRATION_STEP_INTERVAL_US;")
    L.push("  }")
    L.push("")
    L.push("  digitalWrite(cfg.dirPin, dirLevel);")
    L.push("  delayMicroseconds(10);            // let DIR settle before the first edge")
    L.push("  for (long i = 0; i < steps; i++) {")
    L.push("    digitalWrite(cfg.stepPin, HIGH);")
    L.push("    delayMicroseconds(5);")
    L.push("    digitalWrite(cfg.stepPin, LOW);")
    L.push("    delayMicroseconds(intervalUs);")
    L.push("  }")
    L.push("}")
    L.push("")
    L.push("void calibrateDirections() {")
    L.push("  for (uint8_t a = 0; a < AXIS_COUNT; a++) {")
    L.push("    const AxisConfig &cfg = AXIS_CONFIG[a];")
    L.push("    const float here = readEncoderDeg(a);")
    L.push("")
    L.push("    // Largest nudge that is safe whichever way DIR HIGH turns out to move.")
    L.push("    float probeDeg = CALIBRATION_PROBE_DEG;")
    L.push("    if (!cfg.continuousRotation) {")
    L.push("      const float roomUp   = cfg.maxAngleDeg - here;")
    L.push("      const float roomDown = here - cfg.minAngleDeg;")
    L.push("      const float room     = roomUp < roomDown ? roomUp : roomDown;")
    L.push("      if (room < probeDeg) probeDeg = room;")
    L.push("    }")
    L.push("")
    L.push("    if (probeDeg < CALIBRATION_MIN_PROBE_DEG) {")
    L.push("      printAxisName(a);")
    L.push("      Serial.println(F(\": too close to a limit to probe, keeping default\"));")
    L.push("      continue;")
    L.push("    }")
    L.push("")
    L.push("    const long steps = lround(probeDeg * cfg.stepsPerDegree);")
    L.push("    if (steps < 1) continue;")
    L.push("")
    L.push("    pulseBlind(a, HIGH, steps);")
    L.push("    delay(CALIBRATION_SETTLE_MS);")
    L.push("    const float after = readEncoderDeg(a);")
    L.push("")
    L.push("    pulseBlind(a, LOW, steps);       // put it back where it started")
    L.push("    delay(CALIBRATION_SETTLE_MS);")
    L.push("")
    L.push("    const float moved = angleError(after, here, cfg.continuousRotation);")
    L.push("")
    L.push("    // Always report the numbers. \"Inconclusive\" on its own says nothing")
    L.push("    // about WHY: a motor that never turned and an encoder that cannot see")
    L.push("    // the turn look identical until you can compare asked against saw.")
    L.push("    printAxisName(a);")
    L.push("    Serial.print(F(\": asked \")); Serial.print(probeDeg, 2);")
    L.push("    Serial.print(F(\" deg (\"));   Serial.print(steps);")
    L.push("    Serial.print(F(\" steps), saw \")); Serial.print(moved, 2);")
    L.push("    Serial.println(F(\" deg\"));")
    L.push("")
    L.push("    if (fabs(moved) < CALIBRATION_MIN_DETECT_DEG) {")
    L.push("      Serial.println(F(\"  -> inconclusive. Near zero means the motor did not\"));")
    L.push("      Serial.println(F(\"     turn (check EN, current, driver UART address);\"));")
    L.push("      Serial.println(F(\"     a noisy value means the encoder cannot see it.\"));")
    L.push("      continue;")
    L.push("    }")
    L.push("")
    L.push("    dirHighIncreases[a] = (moved > 0.0f);")
    L.push("    Serial.print(F(\"  -> DIR HIGH \"));")
    L.push("    Serial.println(dirHighIncreases[a] ? F(\"increases angle\")")
    L.push("                                       : F(\"decreases angle\"));")
    L.push("  }")
    L.push("}")
    return L.join("\n")
}

function buildMainSection(model) {
    var L = []
    L.push("")
    L.push("// ===========================================================================")
    L.push("// 6. Arduino entry points")
    L.push("// ===========================================================================")
    L.push("")
    L.push("void setup() {")
    L.push("  Serial.begin(115200);")
    L.push("")
    L.push("#if !defined(ARDUINO_ARCH_AVR)")
    L.push("  // Uno R4 / Uno Q: ask for the full ADC resolution. One count becomes")
    L.push("  // 0.022 deg instead of 0.35 deg - a 16x finer encoder on the same wires.")
    L.push("  analogReadResolution(ENCODER_ADC_BITS);")
    L.push("#endif")
    L.push("")
    L.push("  for (uint8_t a = 0; a < AXIS_COUNT; a++) {")
    L.push("    pinMode(AXIS_CONFIG[a].stepPin, OUTPUT);")
    L.push("    pinMode(AXIS_CONFIG[a].dirPin, OUTPUT);")
    L.push("    digitalWrite(AXIS_CONFIG[a].stepPin, LOW);")
    L.push("    dirHighIncreases[a] = true;   // replaced by the probe below")
    L.push("    dirLevelWritten[a]  = -1;")
    L.push("    stepPinRaised[a]    = false;")
    L.push("    stepPhase[a]        = 0.0f;")
    L.push("    stepRate[a]         = 0.0f;")
    L.push("    axisSpeed[a]        = 0.0f;")
    L.push("    bias[a]             = 0.0f;")
    L.push("    lastStallWarnMs[a]  = 0;")
    L.push("  }")
    if (hasEnablePin(model)) {
        L.push("")
        L.push("  // Hold the drivers off until they have been configured.")
        L.push("  pinMode(ENABLE_PIN, OUTPUT);")
        L.push("  digitalWrite(ENABLE_PIN, HIGH);   // active low: HIGH = motors off")
    }
    L.push("")
    if (model.uartEnabled) {
        L.push("  // Microstepping first: everything below measures in steps.")
        L.push("  configureDrivers();")
        L.push("")
    }
    if (hasEnablePin(model)) {
        L.push("  digitalWrite(ENABLE_PIN, LOW);    // drivers configured, motors on")
        L.push("  delay(10);")
        L.push("")
    }
    L.push("  if (ENCODER_MONITOR) {")
    if (hasEnablePin(model)) {
        L.push("    digitalWrite(ENABLE_PIN, HIGH);   // motors off: turn the arm by hand")
    }
    L.push("    Serial.println(F(\"ENCODER MONITOR - motors disabled.\"));")
    L.push("    Serial.println(F(\"Turn each axis by hand; the angle should follow it.\"));")
    L.push("    return;                            // no probe, no sequence")
    L.push("  }")
    L.push("")
    L.push("  Serial.println(F(\"-- encoders before probe --\"));")
    L.push("  reportEncoders();")
    L.push("")
    L.push("  if (DIRECTION_CALIBRATION) {")
    L.push("    Serial.println(F(\"Probing axis directions...\"));")
    L.push("    calibrateDirections();")
    L.push("  }")
    L.push("")
    L.push("  // Learn the arm's true pose. This is what lets it be powered up in any")
    L.push("  // position: nothing has to be driven to a home pose first.")
    L.push("  Serial.println(F(\"-- start pose --\"));")
    L.push("  reportEncoders();")
    L.push("  const uint32_t startUs = micros();")
    L.push("  for (uint8_t a = 0; a < AXIS_COUNT; a++) {")
    L.push("    const float measured = readEncoderDeg(a);")
    L.push("    stepCount[a]         = angleToSteps(a, measured);")
    L.push("    encoderAngle[a]      = measured;")
    L.push("    stepAngleFiltered[a] = stepsToAngle(a, stepCount[a]);")
    L.push("    holdAngle[a]         = measured;")
    L.push("    dirRefStepAngle[a]   = stepAngleFiltered[a];")
    L.push("    dirRefEncoder[a]     = measured;")
    L.push("    encoderSampleUs[a]   = startUs;")
    L.push("  }")
    L.push("  rebaseFirstMoves();")
    L.push("")
    L.push("  bootMs         = millis();")
    L.push("  lastDirCheckMs = bootMs;")
    L.push("  lastPassUs     = micros();")
    L.push("  lastControlUs  = lastPassUs;")
    L.push("  lastEncoderUs  = lastPassUs;")
    L.push("  Serial.println(F(\"Ready.\"));")
    L.push("}")
    L.push("")
    L.push("void loop() {")
    L.push("  if (ENCODER_MONITOR) {")
    L.push("    static uint32_t lastMonitorMs = 0;")
    L.push("    const uint32_t nowMs = millis();")
    L.push("    if ((uint32_t)(nowMs - lastMonitorMs) >= ENCODER_MONITOR_INTERVAL_MS) {")
    L.push("      lastMonitorMs = nowMs;")
    L.push("      reportEncoders();")
    L.push("    }")
    L.push("    return;")
    L.push("  }")
    L.push("")
    L.push("  lowerStepPins();")
    L.push("")
    L.push("  const uint32_t nowUs  = micros();")
    L.push("  const float    passDt = (float)(uint32_t)(nowUs - lastPassUs) * 1e-6f;")
    L.push("  lastPassUs = nowUs;")
    L.push("")
    L.push("  // Every pass: the step pulses, then at most one encoder conversion.")
    L.push("  serviceSteppers(passDt);")
    L.push("  sampleNextEncoder(nowUs);")
    L.push("")
    L.push("  // Every CONTROL_PERIOD_US: where should each axis be, and how fast.")
    L.push("  if ((uint32_t)(nowUs - lastControlUs) < CONTROL_PERIOD_US) return;")
    L.push("  const float controlDt = (float)(uint32_t)(nowUs - lastControlUs) * 1e-6f;")
    L.push("  lastControlUs = nowUs;")
    L.push("")
    L.push("  const uint32_t nowMs       = millis();")
    L.push("  const uint32_t sinceBootMs = nowMs - bootMs;")
    L.push("  const bool     running     = sinceBootMs >= START_DELAY_MS;")
    L.push("  uint32_t       elapsedMs   = running ? sinceBootMs - START_DELAY_MS : 0;")
    L.push("")
    L.push("  if (running && elapsedMs >= SEQUENCE_DURATION_MS) {")
    L.push("    if (REPEAT_SEQUENCE) {")
    L.push("      bootMs    = nowMs - START_DELAY_MS;")
    L.push("      elapsedMs = 0;")
    L.push("      rebaseFirstMoves();              // start the next round from here")
    L.push("    } else {")
    L.push("      elapsedMs = SEQUENCE_DURATION_MS;   // hold the final pose")
    L.push("      if (!sequenceFinished) {")
    L.push("        sequenceFinished = true;")
    L.push("        Serial.println(F(\"Sequence complete.\"));")
    L.push("      }")
    L.push("    }")
    L.push("  }")
    L.push("")
    L.push("  controlTick(running, elapsedMs, controlDt);")
    L.push("")
    L.push("  if ((uint32_t)(nowMs - lastDirCheckMs) >= DIR_CHECK_MS) {")
    L.push("    lastDirCheckMs = nowMs;")
    L.push("    checkDirections();")
    L.push("  }")
    L.push("}")
    return L.join("\n")
}

// -------------------------------------------------------------------------
// Entry point
// -------------------------------------------------------------------------
function generate(blocks, model, result) {
    var timeline = result.timeline ? result.timeline : PlanMath.build(blocks, model)
    var moves = buildMoveTable(model, timeline)

    var parts = []
    parts.push(buildHeader(model, timeline, moves))
    parts.push("")
    parts.push(buildConfigSection(model))
    parts.push("")
    parts.push(buildPlanSection(model, timeline, moves))
    parts.push("")
    parts.push(buildRuntimeSection(model))
    parts.push(buildUartSection(model))
    parts.push(buildCalibrationSection())
    parts.push(buildMainSection(model))
    parts.push("")

    return parts.join("\n")
}
