// ArduinoGenerator.js
//
// Emits an Arduino sketch for a PCA9685-driven servo arm from the timeline.
//
// Design of the generated sketch:
//   * absolute target angles, converted to pulse widths per servo calibration
//   * every movement is a (servo, startMs, durationMs, fromAngle, toAngle) row
//   * loop() interpolates ALL rows that have started, writes one angle per
//     servo per tick, and never calls delay() -- so any number of servos can
//     travel at the same time and none waits for another to finish

.pragma library
.import "RobotModels.js" as RobotModels
.import "PlanMath.js" as PlanMath
.import "ArduinoGeneratorStepper.js" as StepperGenerator

var UPDATE_INTERVAL_MS = 20     // 50 Hz servo refresh

function enumName(joint) {
    return "SERVO_" + joint.id.toUpperCase().replace(/[^A-Z0-9]+/g, "_")
}

function hex8(value) {
    var s = Math.round(value).toString(16).toUpperCase()
    return "0x" + (s.length < 2 ? "0" + s : s)
}

function f(value, decimals) {
    return PlanMath.roundTo(value, decimals === undefined ? 1 : decimals).toFixed(
                decimals === undefined ? 1 : decimals)
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

// -------------------------------------------------------------------------
// Header comment: a human-readable print-out of the timeline
// -------------------------------------------------------------------------
function buildHeader(model, timeline, moves) {
    var lines = []
    lines.push("/*")
    lines.push(" * " + model.name + " – generated movement sequence")
    lines.push(" * Produced by SpaceDragon Robot Programmer. Edits are overwritten on regenerate.")
    lines.push(" *")
    lines.push(" * Controller : " + model.controller)
    lines.push(" * Driver     : " + model.driver + " @ " + hex8(model.i2cAddress))
    lines.push(" * Servos     : " + model.servoType + " (" + model.joints.length + " channels)")
    lines.push(" * Sequence   : " + f(timeline.endTime, 3) + " s, after a "
               + Math.round(model.startDelayMs) + " ms start delay")
    lines.push(" * Startup    : " + (model.startupHoming
                                     ? "servos driven to their start angles"
                                     : "no homing – the arm keeps the pose it is in"))
    lines.push(" * Motion     : " + (model.motionProfile === "easeInOut"
                                     ? "eased (smoothstep) – gentle at both ends"
                                     : "linear – constant speed"))
    lines.push(" *")

    if (moves.length === 0) {
        lines.push(" * The timeline is empty. This sketch only homes the servos.")
    } else {
        lines.push(" * Timeline")
        lines.push(" * " + pad("start", 9) + pad("end", 9) + pad("axis", 10)
                   + pad("from", 9) + pad("to", 9) + "duration")
        for (var i = 0; i < moves.length; ++i) {
            var m = moves[i]
            lines.push(" * " + pad(f(m.start, 2) + " s", 9)
                       + pad(f(m.end, 2) + " s", 9)
                       + pad(m.jointName, 10)
                       + pad(f(m.from) + "°", 9)
                       + pad(f(m.to) + "°", 9)
                       + f(m.duration, 2) + " s"
                       + (m.label ? "   (" + m.label + ")" : ""))
        }
        lines.push(" *")
        lines.push(" * Rows that share a start time begin together; rows never block each other.")
    }

    lines.push(" *")
    for (var c = 0; c < model.constraints.length; ++c) {
        var rule = model.constraints[c]
        lines.push(" * Constraint: " + rule.title + " – " + rule.description
                   + (rule.enabled ? " (checked)" : " (disabled)"))
    }
    lines.push(" */")
    return lines.join("\n")
}

// -------------------------------------------------------------------------
// Flatten the per-joint segments into one chronological move table
// -------------------------------------------------------------------------
function buildMoveTable(blocks, model, timeline) {
    var moves = []
    var blockById = {}
    for (var i = 0; i < blocks.length; ++i)
        blockById[blocks[i].blockId] = blocks[i]

    for (var jointId in timeline.segments) {
        var joint = RobotModels.findJoint(model, jointId)
        var segs = timeline.segments[jointId]
        for (var s = 0; s < segs.length; ++s) {
            var seg = segs[s]
            var block = blockById[seg.blockId]
            var label = ""
            if (joint.role === "gripper" && block) {
                var cmd = RobotModels.gripperCommand(joint, block.commandId)
                label = cmd ? cmd.name : ""
            }
            moves.push({
                servo: enumName(joint),
                jointName: joint.name,
                start: seg.start,
                end: seg.end,
                duration: seg.duration,
                from: seg.from,
                to: seg.to,
                label: label
            })
        }
    }

    moves.sort(function (a, b) {
        if (Math.abs(a.start - b.start) > 1e-6)
            return a.start - b.start
        return a.servo < b.servo ? -1 : (a.servo > b.servo ? 1 : 0)
    })
    return moves
}

// -------------------------------------------------------------------------
// Sketch sections
// -------------------------------------------------------------------------
function buildConfigSection(model) {
    var L = []
    L.push("// ===========================================================================")
    L.push("// 1. Hardware configuration")
    L.push("//    Mirror of the Robot Model page. Change it there and regenerate, or")
    L.push("//    tweak the numbers here while calibrating on the bench.")
    L.push("// ===========================================================================")
    L.push("")
    // Names are deliberately NOT prefixed PCA9685_: the Adafruit header
    // already defines PCA9685_I2C_ADDRESS and friends as macros, and a macro
    // would textually replace our constant's name.
    L.push("static const uint8_t  PWM_DRIVER_I2C_ADDRESS  = " + hex8(model.i2cAddress) + ";")
    L.push("static const uint16_t PWM_DRIVER_FREQUENCY_HZ = " + model.pwmFrequencyHz
           + ";      // standard analog servo rate")
    L.push("// Actual PCA9685 crystal. 25 MHz is the datasheet figure, but most")
    L.push("// boards measure 26-27 MHz. If the servos buzz or the travel range is")
    L.push("// off, measure the real output frequency and correct this value --")
    L.push("// every pulse width scales with it.")
    L.push("static const uint32_t PWM_DRIVER_OSCILLATOR_HZ = " + model.oscillatorHz + "UL;")
    L.push("")
    L.push("// Servo command range as specified by the " + model.servoType + " datasheet.")
    L.push("static const float SERVO_NOMINAL_MIN_DEG = " + f(RobotModels.NOMINAL_MIN) + "f;")
    L.push("static const float SERVO_NOMINAL_MAX_DEG = " + f(RobotModels.NOMINAL_MAX) + "f;")
    L.push("")
    L.push("Adafruit_PWMServoDriver pwmDriver = Adafruit_PWMServoDriver(PWM_DRIVER_I2C_ADDRESS);")
    L.push("")
    L.push("// Logical servo names. The PCA9685 channel each one uses is in SERVO_CONFIG,")
    L.push("// so re-wiring the expander never changes the movement table below.")
    L.push("enum ServoId : uint8_t {")
    for (var i = 0; i < model.joints.length; ++i) {
        L.push("  " + pad(enumName(model.joints[i]) + ",", 18)
               + "// " + model.joints[i].name + " – " + model.joints[i].subtitle)
    }
    L.push("  SERVO_COUNT")
    L.push("};")
    L.push("")
    L.push("struct ServoConfig {")
    L.push("  uint8_t  channel;       // PCA9685 output channel")
    L.push("  uint16_t minPulseUs;    // pulse width at SERVO_NOMINAL_MIN_DEG")
    L.push("  uint16_t maxPulseUs;    // pulse width at SERVO_NOMINAL_MAX_DEG")
    L.push("  float    minAngleDeg;   // mechanical limit of this robot")
    L.push("  float    maxAngleDeg;")
    L.push("  float    startAngleDeg; // pose the plan was built from; only")
    L.push("                          // actually commanded when STARTUP_HOMING")
    L.push("  bool     inverted;      // true when the servo is mounted mirrored")
    L.push("};")
    L.push("")
    L.push("// Every servo is calibrated on its own: pulse widths, limits and mounting")
    L.push("// direction may all differ between channels.")
    L.push("static const ServoConfig SERVO_CONFIG[SERVO_COUNT] = {")
    for (i = 0; i < model.joints.length; ++i) {
        var j = model.joints[i]
        L.push("  /* " + pad(enumName(j), 16) + "*/ { "
               + padLeft(j.channel, 2) + ", "
               + padLeft(j.minPulseUs, 4) + ", " + padLeft(j.maxPulseUs, 4) + ", "
               + padLeft(f(j.mechMin) + "f", 7) + ", " + padLeft(f(j.mechMax) + "f", 7) + ", "
               + padLeft(f(j.homeAngle) + "f", 7) + ", "
               + (j.inverted ? "true " : "false") + " }"
               + (i < model.joints.length - 1 ? "," : ""))
    }
    L.push("};")

    var gripper = null
    for (i = 0; i < model.joints.length; ++i) {
        if (model.joints[i].role === "gripper")
            gripper = model.joints[i]
    }
    if (gripper && gripper.commands) {
        L.push("")
        L.push("// Named gripper positions (absolute servo angles).")
        for (i = 0; i < gripper.commands.length; ++i) {
            var c = gripper.commands[i]
            L.push("static const float GRIPPER_" + c.id.toUpperCase() + "_ANGLE_DEG = "
                   + f(c.angle) + "f;")
        }
    }
    return L.join("\n")
}

function buildPlanSection(model, timeline, moves) {
    var L = []
    L.push("// ===========================================================================")
    L.push("// 2. Movement plan")
    L.push("//    One row per movement, in timeline order. Rows are independent: two rows")
    L.push("//    with the same startMs start together, and overlapping rows on different")
    L.push("//    servos simply run at the same time.")
    L.push("// ===========================================================================")
    L.push("")
    L.push("struct ServoMove {")
    L.push("  uint8_t  servo;")
    L.push("  uint32_t startMs;       // relative to the start of the sequence")
    L.push("  uint32_t durationMs;")
    L.push("  float    fromAngleDeg;  // commanded position when this move begins")
    L.push("  float    toAngleDeg;    // absolute target position")
    L.push("};")
    L.push("")

    if (moves.length === 0) {
        L.push("// The timeline is empty – this sketch commands no movement.")
        L.push("static const ServoMove MOVE_PLAN[1] = {")
        L.push("  { 0, 0, 0, 0.0f, 0.0f }   // placeholder, not executed")
        L.push("};")
        L.push("static const uint8_t  MOVE_COUNT = 0;")
    } else {
        L.push("static const ServoMove MOVE_PLAN[] = {")
        for (var i = 0; i < moves.length; ++i) {
            var m = moves[i]
            L.push("  // t = " + f(m.start, 3) + " s – " + m.jointName + " "
                   + f(m.from) + "° → " + f(m.to) + "° over " + f(m.duration, 3) + " s"
                   + (m.label ? "  (" + m.label + ")" : ""))
            L.push("  { " + pad(m.servo + ",", 18)
                   + padLeft(Math.round(m.start * 1000), 7) + ", "
                   + padLeft(Math.round(m.duration * 1000), 7) + ", "
                   + padLeft(f(m.from) + "f", 8) + ", " + padLeft(f(m.to) + "f", 8) + " }"
                   + (i < moves.length - 1 ? "," : ""))
        }
        L.push("};")
        L.push("static const uint8_t  MOVE_COUNT = sizeof(MOVE_PLAN) / sizeof(MOVE_PLAN[0]);")
    }

    L.push("static const uint32_t SEQUENCE_DURATION_MS = "
           + Math.round(timeline.endTime * 1000) + "UL;")
    L.push("")
    L.push("// ---- Startup and holding behaviour ----------------------------------")
    L.push("")
    L.push("// false: no channel is touched until a servo's first movement begins, so")
    L.push("//        the arm starts from whatever pose it is already in.")
    L.push("// true : every servo is driven to its startAngleDeg in setup().")
    L.push("static const bool     STARTUP_HOMING       = " + (model.startupHoming ? "true" : "false")
           + ";")
    L.push("// Non-blocking hold-off before the timeline runs. Nothing is commanded")
    L.push("// during it; with homing on it doubles as the settling time.")
    L.push("static const uint32_t START_DELAY_MS       = " + Math.round(model.startDelayMs) + "UL;")
    L.push("// Re-send the current target this often. A single dropped I2C write can")
    L.push("// otherwise leave a servo holding a stale position. 0 disables.")
    L.push("static const uint32_t HOLD_REFRESH_MS      = " + Math.round(model.holdRefreshMs) + "UL;")
    L.push("// true cuts PWM when the sequence ends; the servos go limp instead of")
    L.push("// holding their final pose.")
    L.push("static const bool     RELEASE_AFTER_SEQUENCE = "
           + (model.releaseAfterSequence ? "true" : "false") + ";")
    L.push("static const uint16_t UPDATE_INTERVAL_MS   = " + UPDATE_INTERVAL_MS
           + ";   // servo refresh period")
    L.push("static const bool     REPEAT_SEQUENCE      = false;  // set true to loop forever")
    return L.join("\n")
}

function buildRuntimeSection(model) {
    var eased = model.motionProfile === "easeInOut"

    var L = []
    L.push("// ===========================================================================")
    L.push("// 3. Runtime")
    L.push("// ===========================================================================")
    L.push("")
    L.push("static uint16_t lastWrittenTicks[SERVO_COUNT];")
    L.push("static bool     servoEngaged[SERVO_COUNT];   // has this servo been commanded yet?")
    L.push("static uint32_t bootMs            = 0;")
    L.push("static uint32_t lastUpdateMs      = 0;")
    L.push("static uint32_t lastHoldRefreshMs = 0;")
    L.push("static bool     sequenceFinished  = false;")
    L.push("")
    L.push("// Shape of a movement between 0 and 1.")
    if (eased) {
        L.push("// Smoothstep: the servo eases away from the start angle and settles into")
        L.push("// the target instead of slamming into both ends. This is the same curve")
        L.push("// the planner used to validate the sequence -- change one, change both.")
    } else {
        L.push("// Linear: constant speed for the whole travel. Matches the planner.")
    }
    L.push("float shapeProgress(float progress) {")
    L.push("  if (progress <= 0.0f) return 0.0f;")
    L.push("  if (progress >= 1.0f) return 1.0f;")
    if (eased)
        L.push("  return progress * progress * (3.0f - 2.0f * progress);")
    else
        L.push("  return progress;")
    L.push("}")
    L.push("")
    L.push("// Convert an absolute angle to a PCA9685 tick count using this servo's")
    L.push("// own pulse-width calibration.")
    L.push("uint16_t angleToTicks(uint8_t servo, float angleDeg) {")
    L.push("  const ServoConfig &cfg = SERVO_CONFIG[servo];")
    L.push("")
    L.push("  // Never command past the mechanical limits, whatever the plan says.")
    L.push("  if (angleDeg < cfg.minAngleDeg) angleDeg = cfg.minAngleDeg;")
    L.push("  if (angleDeg > cfg.maxAngleDeg) angleDeg = cfg.maxAngleDeg;")
    L.push("")
    L.push("  const float shaftAngle = cfg.inverted")
    L.push("      ? (SERVO_NOMINAL_MAX_DEG - (angleDeg - SERVO_NOMINAL_MIN_DEG))")
    L.push("      : angleDeg;")
    L.push("")
    L.push("  const float span    = SERVO_NOMINAL_MAX_DEG - SERVO_NOMINAL_MIN_DEG;")
    L.push("  const float ratio   = (shaftAngle - SERVO_NOMINAL_MIN_DEG) / span;")
    L.push("  const float pulseUs = cfg.minPulseUs + (cfg.maxPulseUs - cfg.minPulseUs) * ratio;")
    L.push("")
    L.push("  // One PWM period is 4096 ticks long.")
    L.push("  const float usPerTick = 1000000.0f / ((float)PWM_DRIVER_FREQUENCY_HZ * 4096.0f);")
    L.push("  return (uint16_t)((pulseUs / usPerTick) + 0.5f);")
    L.push("}")
    L.push("")
    L.push("// Write one servo. Unchanged values are skipped so the I2C bus stays free")
    L.push("// for the servos that are actually moving; `force` overrides that for the")
    L.push("// periodic hold refresh and for the final on-target write.")
    L.push("void writeServoAngle(uint8_t servo, float angleDeg, bool force) {")
    L.push("  const uint16_t ticks = angleToTicks(servo, angleDeg);")
    L.push("  if (!force && servoEngaged[servo] && ticks == lastWrittenTicks[servo]) return;")
    L.push("  lastWrittenTicks[servo] = ticks;")
    L.push("  servoEngaged[servo]     = true;")
    L.push("  pwmDriver.setPWM(SERVO_CONFIG[servo].channel, 0, ticks);")
    L.push("}")
    L.push("")
    L.push("// Stop driving every channel. Servos without a pulse are not held.")
    L.push("void releaseAllServos() {")
    L.push("  for (uint8_t s = 0; s < SERVO_COUNT; s++) {")
    L.push("    pwmDriver.setPWM(SERVO_CONFIG[s].channel, 0, 4096);   // full-off bit")
    L.push("    servoEngaged[s] = false;")
    L.push("  }")
    L.push("}")
    L.push("")
    L.push("// Evaluate the whole plan for one instant and write each servo at most once.")
    L.push("// Nothing here blocks, so servos move simultaneously and independently.")
    L.push("void applyPlanAt(uint32_t elapsedMs, bool force) {")
    L.push("  float targetAngleDeg[SERVO_COUNT];")
    L.push("  bool  commanded[SERVO_COUNT];")
    L.push("")
    L.push("  for (uint8_t s = 0; s < SERVO_COUNT; s++) {")
    L.push("    targetAngleDeg[s] = SERVO_CONFIG[s].startAngleDeg;")
    L.push("    // Without homing a servo stays untouched until its first move runs,")
    L.push("    // which is what lets the arm keep the pose it powered up in.")
    L.push("    commanded[s] = STARTUP_HOMING;")
    L.push("  }")
    L.push("")
    L.push("  for (uint8_t i = 0; i < MOVE_COUNT; i++) {")
    L.push("    const ServoMove &move = MOVE_PLAN[i];")
    L.push("    if (elapsedMs < move.startMs) continue;   // has not started yet")
    L.push("")
    L.push("    // Finished moves keep reporting their target, which is exactly the")
    L.push("    // \"hold position until the next command\" behaviour we want.")
    L.push("    float progress = 1.0f;")
    L.push("    if (move.durationMs > 0) {")
    L.push("      const uint32_t movingMs = elapsedMs - move.startMs;")
    L.push("      if (movingMs < move.durationMs) {")
    L.push("        progress = (float)movingMs / (float)move.durationMs;")
    L.push("      }")
    L.push("    }")
    L.push("")
    L.push("    // Later rows for the same servo overwrite earlier ones, so each servo")
    L.push("    // ends up with exactly one target per tick.")
    L.push("    targetAngleDeg[move.servo] =")
    L.push("        move.fromAngleDeg")
    L.push("        + (move.toAngleDeg - move.fromAngleDeg) * shapeProgress(progress);")
    L.push("    commanded[move.servo] = true;")
    L.push("  }")
    L.push("")
    L.push("  for (uint8_t s = 0; s < SERVO_COUNT; s++) {")
    L.push("    if (commanded[s]) writeServoAngle(s, targetAngleDeg[s], force);")
    L.push("  }")
    L.push("}")
    return L.join("\n")
}

function buildGripperSection(model) {
    var gripper = null
    for (var i = 0; i < model.joints.length; ++i) {
        if (model.joints[i].role === "gripper")
            gripper = model.joints[i]
    }
    if (!gripper || !gripper.commands)
        return ""

    var L = []
    L.push("")
    L.push("// ---------------------------------------------------------------------------")
    L.push("// Gripper commands. The sequence above already contains the gripper moves;")
    L.push("// these helpers are here for manual control from your own code.")
    L.push("// ---------------------------------------------------------------------------")
    for (i = 0; i < gripper.commands.length; ++i) {
        var c = gripper.commands[i]
        var fn = "gripper" + c.name.charAt(0).toUpperCase() + c.name.slice(1)
        L.push("void " + fn + "() { writeServoAngle(" + enumName(gripper)
               + ", GRIPPER_" + c.id.toUpperCase() + "_ANGLE_DEG, true); }  // "
               + f(c.angle) + "°")
    }
    return L.join("\n")
}

function buildMainSection() {
    var L = []
    L.push("")
    L.push("// ===========================================================================")
    L.push("// 4. Arduino entry points")
    L.push("// ===========================================================================")
    L.push("")
    L.push("void setup() {")
    L.push("  Serial.begin(115200);")
    L.push("")
    L.push("  for (uint8_t s = 0; s < SERVO_COUNT; s++) {")
    L.push("    lastWrittenTicks[s] = 0;")
    L.push("    servoEngaged[s]     = false;")
    L.push("  }")
    L.push("")
    L.push("  Wire.begin();")
    L.push("  pwmDriver.begin();")
    L.push("  pwmDriver.setOscillatorFrequency(PWM_DRIVER_OSCILLATOR_HZ);")
    L.push("  pwmDriver.setPWMFreq(PWM_DRIVER_FREQUENCY_HZ);")
    L.push("")
    L.push("  if (STARTUP_HOMING) {")
    L.push("    // Drive the arm to a known pose; START_DELAY_MS then lets it settle.")
    L.push("    for (uint8_t s = 0; s < SERVO_COUNT; s++) {")
    L.push("      writeServoAngle(s, SERVO_CONFIG[s].startAngleDeg, true);")
    L.push("    }")
    L.push("  }")
    L.push("  // Otherwise no channel is written here, so the arm holds the pose it")
    L.push("  // powered up in until its first movement is due.")
    L.push("")
    L.push("  bootMs            = millis();")
    L.push("  lastUpdateMs      = bootMs;")
    L.push("  lastHoldRefreshMs = bootMs;")
    L.push("}")
    L.push("")
    L.push("void loop() {")
    L.push("  const uint32_t now = millis();")
    L.push("")
    L.push("  // millis()-based pacing: no delay() anywhere, so the sketch stays")
    L.push("  // responsive and every servo is updated on the same tick.")
    L.push("  if ((uint32_t)(now - lastUpdateMs) < UPDATE_INTERVAL_MS) return;")
    L.push("  lastUpdateMs = now;")
    L.push("")
    L.push("  const uint32_t sinceBootMs = now - bootMs;")
    L.push("")
    L.push("  // Hold-off before the timeline starts. Nothing is commanded during it.")
    L.push("  if (sinceBootMs < START_DELAY_MS) return;")
    L.push("")
    L.push("  uint32_t elapsedMs = sinceBootMs - START_DELAY_MS;")
    L.push("")
    L.push("  if (elapsedMs >= SEQUENCE_DURATION_MS) {")
    L.push("    if (REPEAT_SEQUENCE) {")
    L.push("      bootMs    = now - START_DELAY_MS;   // loop without re-running the hold-off")
    L.push("      elapsedMs = 0;")
    L.push("    } else {")
    L.push("      elapsedMs = SEQUENCE_DURATION_MS;   // hold the final pose")
    L.push("")
    L.push("      if (!sequenceFinished) {")
    L.push("        sequenceFinished = true;")
    L.push("        applyPlanAt(elapsedMs, true);     // one forced write, exactly on target")
    L.push("        if (RELEASE_AFTER_SEQUENCE) {")
    L.push("          releaseAllServos();")
    L.push("          Serial.println(F(\"Sequence complete - servos released.\"));")
    L.push("        } else {")
    L.push("          Serial.println(F(\"Sequence complete - holding final pose.\"));")
    L.push("        }")
    L.push("        return;")
    L.push("      }")
    L.push("")
    L.push("      if (RELEASE_AFTER_SEQUENCE) return;   // released: stay off the bus")
    L.push("    }")
    L.push("  }")
    L.push("")
    L.push("  // Re-send the current target now and then, so one dropped I2C write")
    L.push("  // cannot leave a servo sitting at a stale position.")
    L.push("  bool force = false;")
    L.push("  if (HOLD_REFRESH_MS > 0 && (uint32_t)(now - lastHoldRefreshMs) >= HOLD_REFRESH_MS) {")
    L.push("    lastHoldRefreshMs = now;")
    L.push("    force = true;")
    L.push("  }")
    L.push("")
    L.push("  applyPlanAt(elapsedMs, force);")
    L.push("}")
    return L.join("\n")
}

// -------------------------------------------------------------------------
// Entry point. `result` is the object returned by Validator.validate().
//
// Each actuator family gets its own generator, because the resulting sketches
// have almost nothing in common: one writes PWM pulse widths over I2C, the
// other counts steps against encoder feedback.
// -------------------------------------------------------------------------
function generate(blocks, model, result) {
    if (model.driveType === "stepper")
        return StepperGenerator.generate(blocks, model, result)
    return generateServoPwm(blocks, model, result)
}

function generateServoPwm(blocks, model, result) {
    var timeline = result.timeline ? result.timeline : PlanMath.build(blocks, model)
    var moves = buildMoveTable(blocks, model, timeline)

    var parts = []
    parts.push(buildHeader(model, timeline, moves))
    parts.push("")
    parts.push("#include <Wire.h>")
    parts.push("#include <Adafruit_PWMServoDriver.h>   // Library Manager: \"Adafruit PWM Servo Driver\"")
    parts.push("")
    parts.push(buildConfigSection(model))
    parts.push("")
    parts.push(buildPlanSection(model, timeline, moves))
    parts.push("")
    parts.push(buildRuntimeSection(model))
    var gripperSection = buildGripperSection(model)
    if (gripperSection)
        parts.push(gripperSection)
    parts.push(buildMainSection())
    parts.push("")

    return parts.join("\n")
}

// Placeholder shown instead of executable code when validation fails.
function generateRejection(model, result) {
    var L = []
    L.push("/*")
    L.push(" * NO CODE GENERATED")
    L.push(" *")
    L.push(" * The movement plan for " + (model ? model.name : "the selected robot")
           + " is not executable yet.")
    L.push(" * Fix the problems below in the Blocks module, then convert again.")
    L.push(" *")

    var errors = []
    for (var i = 0; i < result.issues.length; ++i) {
        if (result.issues[i].severity === "error")
            errors.push(result.issues[i])
    }
    for (i = 0; i < errors.length; ++i) {
        L.push(" * " + (i + 1) + ". " + errors[i].title)
        L.push(" *    " + errors[i].message)
        if (errors[i].hint)
            L.push(" *    → " + errors[i].hint)
        L.push(" *")
    }
    L.push(" * Generating a sketch from an invalid plan could drive the arm into itself,")
    L.push(" * so the sequence is withheld on purpose.")
    L.push(" */")
    return L.join("\n")
}
