# SpaceDragon Robot Programmer

Qt Design Studio (Community) project. Visual, block-based movement programming
for servo robot arms, with automatic Arduino code generation.

Supported robots:

* **Dragon-Arm Demo** — 3 axes + gripper, MG996R servos on a PCA9685 PWM
  expander, Arduino Uno over I²C. `driveType: "servoPwm"`.
* **Dragon-Arm One** — 5 axes, NEMA 17 steppers on TMC2209 (axes 1–2) and
  TMC2208 (axes 3–5), step mode set over UART, MT6701 absolute encoders on
  analog pins. Runs on an **Uno R4**, sometimes an **Uno Q**.
  `driveType: "stepper"`.

### Drive types

`model.driveType` is the main fork in the codebase. It selects the code
generator, the hardware fields the config page shows, and which motion profile
applies. Adding a third actuator family means a new `driveType`, a new
generator, and a branch in `JointConfigRow.qml` — not changes scattered
everywhere.

Stepper specifics worth knowing:

* Resolution is `motorFullStepsPerRev × microsteps × gearRatio / 360`. At full
  step that is **5 steps/deg** on the 9:1 axes and **0.556 steps/deg (1.8°/step)**
  on the direct-drive Axis-5; half step doubles both.
* Axis-1 reads −150…+150 because its encoder seam sits opposite the arm's
  centre; `encoderOffsetDeg: 180` moves the usable 30…330 band to −150…+150.
* The generated sketch reads all encoders at boot, then **rewrites the first
  move of each axis to start from the measured angle** (`rebaseFirstMoves()`).
  Without that the arm lurches from its real pose to the planned one the instant
  the plan starts.

#### The hybrid controller (generated stepper sketch)

The step count is the fast, exact, noise-free position; the encoder is the
truth about the *arm*. Rules, each learned the hard way:

* **The encoder never drives a motor directly.** It slowly corrects a `bias`
  between the two, only above the deadband (`toleranceDeg`) and never faster
  than `maxCorrectionDegPerSec`. Feeding the raw encoder (0.35° per count on
  an R3, 1–2° of noise) to the motors makes them shake constantly.
* **Compare like with like.** The encoder is low-pass filtered, so the step
  angle goes through the *same* filter at the same instant
  (`stepAngleFiltered`). Comparing a lagging encoder with an unfiltered step
  count reads the filter's own delay (~1° at 60°/s) as an error and drags the
  arm around at the end of every fast move.
* **Feedforward, then correct.** Each motor runs at the plan's own S-curve
  speed (`shapeVelocity()` — must match `PlanMath.profileVelocity()`), plus
  `trackingGain × error` clamped to the speed it can still stop from. Pure
  error-driven control lags in proportion to speed.
* **Steps come from a phase accumulator** (`stepPhase`), never a "walk to the
  target, then stop" follower. The follower reset to zero speed every time it
  caught a slowly moving target and emitted stop-start bursts — the original
  "sometimes shaky" bug.
* **Nothing in `loop()` may block for more than one ADC conversion.** Encoders
  are sampled one channel per pass, round-robin. The old ~2 ms blocking reads
  froze every motor while they ran.
* **No timer or ADC registers.** The sketch must run unchanged on an Uno R4
  (Renesas) and an Uno Q (STM32/Zephyr); register-level code cannot. Non-AVR
  boards get `analogReadResolution(14)` (0.022°/count) behind
  `#if !defined(ARDUINO_ARCH_AVR)`.
* **Uno Q cautions (unverified):** its MCU runs at 3.3 V, so the MT6701s must
  be powered from 3.3 V there, and a 3.3 V STEP/DIR high may be below the TMC
  input threshold if VIO is 5 V. Its core may not ship `SoftwareSerial`.
* `nominalMin/Max == mechMin/Max` for steppers, so out-of-range is prevented at
  the slider rather than reported by the validator.

#### Carrier board wiring (as built)

6× StepStick carrier, KiCad project in `<TMC driver board KiCad project>`. Uno pin
budget is full: **D2–D11** STEP/DIR ×5, **A1–A5** encoders, **A0** shared EN
(active low), **D12** UART TX with **D13** as a dummy RX that SoftwareSerial
insists on. D0/D1 stay free for USB debug. Never put EN on D13 — the bootloader
blinks it.

* **Microstepping is set over UART, not by the MS pins** — the TMC2208 MS pins
  cannot select full step at all. MS1=5V/MS2=GND is only the power-up default.
  `GCONF` bits 6 (`pdn_disable`) and 7 (`mstep_reg_select`) must both be set or
  the MS pins keep control and the `CHOPCONF` MRES write is silently ignored.
  Step mode is board-wide: one TX line, nothing is read back.

* **The board carries MIXED drivers, so the config is sent once per address.**
  TMC2209 on axes 1–2, TMC2208 on axes 3–5. A **TMC2208's UART address is fixed
  at 0** — it does not accept any other. A TMC2209 takes its address from
  MS1/MS2, and 5V/GND makes it **1**. A datagram only reaches the address it is
  stamped with, so `uartSlaveAddresses: [0, 1]` and `configureDrivers()` loops
  over them.

  Getting this wrong fails *silently and asymmetrically*: the un-addressed
  drivers stay on their MS-pin default, so those axes run at the wrong step
  scale while the others are fine. The signature is an axis that covers exactly
  **half** (or double) the distance to its target on each run, creeping toward
  it across resets and looking as though it is ignoring the encoder.
* **Configure UART before the direction probe.** The probe steps blind and
  measures with the encoder, so it has to know how far one step goes. A TMC2209
  still at its 1/32 power-up default would move ~1/16 of the expected amount
  and every axis would report "inconclusive".
* **Encoder tolerance has a floor of `TOLERANCE_STEPS` (1.4) steps.** A
  tolerance finer than one step makes the axis hunt: it corrects, overshoots by
  a step, corrects back, forever. `toleranceBaseDeg` is the user's value;
  `toleranceDeg` is that raised to the floor and recomputed whenever
  microstepping or gearing changes. Axis-5 at full step is 1.8°/step, so it
  lands at 2.5°.
* **Never clamp an axis's *holding* target to the mechanical limits** — only
  targets that came from a move. Clamping a hold turns a limit into a
  destination: an arm powered up outside its configured range, or with a wrong
  encoder offset, drives itself to the end-stop before the sequence starts.

---

## Running it

Paths in angle brackets are placeholders for your own install folders:
`<Qt>` is the Qt installation root (e.g. `C:\Qt`), `<project folder>` is this
repository.

The app itself is QML-only — no C++, no compile step. (`packaging/` adds an
optional release build; it is never needed to edit or run the app. See
**Releasing** at the end.)

Design Studio (live preview, edit as you go):

```bash
& "<Qt>\Tools\QtDesignStudio\bin\qtdesignstudio.exe" "<project folder>\DragonArmStudio.qmlproject"
```

Straight from the command line (fastest iteration loop):

```bash
& "<Qt>\6.11.2\mingw_64\bin\qml.exe" -I imports content/App.qml
```

The `-I imports` is required: it puts the `DragonArm` module on the import path.
`.qmlproject` already declares the same path via `importPaths`.

Verified against **Qt 6.11.2 (mingw_64)** and **Qt 6.8.7** (the runtime QDS 4.8.3
uses for live preview). Keep imports version-less and avoid APIs newer than 6.8
so both keep working.

---

## Architecture

Strict one-way dependency: **UI → singletons → JS logic**. The JS layer never
imports Qt types, which is what makes it testable and portable.

```
imports/DragonArm/          the module -- all state and all logic
  qmldir                    declares the four singletons
  Theme.qml                 colours, spacing, fonts          (singleton)
  RobotLibrary.qml          robot catalogue + current model  (singleton)
  MovementPlan.qml          the timeline, THE document       (singleton)
  AppState.qml              navigation, selection, zoom, drag, code cache (singleton)
  RobotModels.js            hardware catalogue (pure data)
  Kinematics.js             tool position <-> axis angles, tool-move paths
  PlanMath.js               blocks -> per-joint motion segments, motion profiles
  Validator.js              checks a plan against a robot model
  ArduinoGenerator.js       dispatches on driveType; holds the servoPwm sketch
  ArduinoGeneratorStepper.js  the STEP/DIR + encoder sketch

content/                    the UI, one folder per module
  App.qml                   Window (mainFile)
  MainShell.qml             sidebar + workspace, drag proxy, robot dialog
  common/                   reusable widgets (PanelCard, AppButton, ParameterSlider, ...)
    galaxy/                 the theme's effects: GalaxyBackground, FireflyLayer,
                            FireflyEmitter, SpotLight, GlowShadow, LogoMark
  fonts/                    Manrope-Variable.ttf + OFL.txt (loaded by App.qml)
  nav/                      NavSidebar, NavButton, RobotModelDialog, JointConfigRow
  home/                     HomeModule, RobotCarousel, CarouselSlide, CarouselArrow
  blocks/                   BlocksModule + palette, workspace, inspector, timeline
  code/                     CodeModule, CodeEditorView, SyntaxHighlight.js
  view3d/                   View3DModule, RobotViewport, PlaybackPanel, PoseController,
                            CameraController
    rigs/dragon-arm-one/    GENERATED: DragonArmOneRig.qml + meshes/*.mesh + rig.json
  images/                   artwork drop-in point (see its README)

tools/                      asset pipeline, not part of the running app
  export_3d_model.ps1       rebuilds the 3D rig: Blender -> GLB -> balsam -> content/view3d/rigs
  export_3d_model.py        the Blender half (bakes, decimates, writes the rig QML)

packaging/                  release build only — not part of the running app
  main.cpp                  thin launcher; embeds content/ + imports/ as resources
  CMakeLists.txt            builds SpaceDragon.exe
  installer.iss             Inno Setup script for the Windows installer
  spacedragon.ico           app icon (also content/images/appicon.png)
  appicon.rc.in             icon + version metadata, configured by CMake
```

### Responsibilities, kept separate on purpose

| Concern | Lives in |
| --- | --- |
| Robot hardware description | `RobotModels.js` (data), `RobotLibrary.qml` (selection + edits) |
| Timeline / execution timing | `MovementPlan.qml` |
| Trajectory maths | `PlanMath.js` |
| Arm geometry, inverse kinematics | `Kinematics.js` (data in `model.kinematics`) |
| Constraint validation | `Validator.js` |
| Arduino output | `ArduinoGenerator.js` |
| View state | `AppState.qml` |
| Everything visual | `content/` |

---

## Invariants — do not break these

1. **Angles are absolute.** `Axis-1 | 60° | 6s` means "go to servo position 60°",
   never "rotate 60° further". A block's start angle is derived: the joint's
   `homeAngle`, or the target of the previous block on the same joint.
   Moving a block along the timeline must never change its target angle.

   `homeAngle` is the **assumed** starting pose — the planner and validator need
   *some* reference, because open-loop servos cannot report where they are. It is
   only physically commanded when `startupHoming` is on (off by default), so the
   UI calls it "Start angle".

   **Tool moves are the one relative block.** "Up 50 mm" has no absolute
   angle of its own; `PlanMath.build()` derives its angles from the pose every
   axis has been commanded to when it starts. So moving a tool move past
   another block *does* change the angles it produces — that is its meaning,
   not a bug. Axis blocks stay absolute, and an axis block after a tool move
   starts from the angle that move ends on. See **Tool moves** below.

2. **The timeline is the source of truth.** Everything — validation, the block
   list, the generated sketch — is derived from `MovementPlan.blocks`. Nothing
   caches a second copy of the plan.

3. **Constraints are validated over the whole trajectory, not at endpoints.**
   Two individually legal blocks can still sweep the arm through an illegal pose
   while both servos are travelling. `Validator.js` samples every joint's
   commanded position every 20 ms across the entire plan. Endpoint-only checking
   is wrong and will let real collisions through.

4. **Never silently change a user's target angle.** Out-of-range values are
   reported as issues and the blocks are highlighted; they are not clamped into
   legality. (Angles *are* clamped to the servo's 0–180° command range on input,
   because a value outside it is not expressible at all.)

5. **Nothing in the motion path may block.** The timeline is executed entirely
   from `millis()`/`micros()` so axes move simultaneously and independently, and
   the start-up hold-off is a non-blocking `START_DELAY_MS` check in `loop()`.

   The one permitted exception is the stepper arm's **startup direction probe**,
   which runs once in `setup()` before any timeline motion and is inherently
   sequential. It uses `delay()`/`delayMicroseconds()` and that is correct;
   turning it into a state machine would buy nothing. Nothing else may.

5b. **The motion profile must be the same curve in both places.**
   `PlanMath.applyProfile()` and the generated `shapeProgress()` describe the
   identical curve — smoothstep for servos, a cosine **S-curve** ramp for
   steppers (`motionProfile: "scurve"`; `"trapezoid"` still exists). If they
   diverge, the validator is checking a trajectory the arm does not actually
   follow. Change one, change the other. The ramp fraction is per block, so it
   travels on the segment (`seg.ramp`), not on the model.

   S-curve facts that the limits depend on: peak speed is `1/(1−r)` × average,
   the same as the trapezoid, but peak acceleration is **π/2 × higher** than a
   straight ramp of the same length (`accelShapeFactor`). `naturalDuration()` and
   `segmentPeaks()` both apply it. To verify a change, extract `shapeProgress()`
   from a generated sketch, compile it natively with g++, and diff its output
   against `PlanMath.applyProfile()` at the same points. They must match to
   six decimals.

   The same rule covers the **tool-move spline**: `Kinematics.pathAngle()` /
   `pathSlope()` and the sketch's functions of the same names are one
   Catmull-Rom curve written twice. The simulation harness checks it (see
   **Checking changes**): 190 poses, worst difference 0.00005°.

5d. **Speed and acceleration limits are errors, not warnings, on steppers.**
   A servo asked to move too fast just lags. A stepper *loses steps*, and its
   open-loop position is then wrong for the rest of the sequence. `naturalDuration()`
   must therefore satisfy BOTH the speed and the acceleration ceiling — an early
   version only checked speed, and every proposed default movement was rejected
   by the validator it was supposed to satisfy.

5c. **Never prefix a generated identifier with `PCA9685_`.** The Adafruit
   header defines `PCA9685_I2C_ADDRESS`, `PCA9685_MODE1`, `FREQUENCY_OSCILLATOR`
   and ~30 more as *macros*; a matching constant name gets textually replaced and
   fails to compile. Generated constants use `PWM_DRIVER_*`, `SERVO_*`,
   `MOVE_*`. The struct is `ServoMove`, not `Move`.

6. **Colours come from `Theme`.** No hex literals in `content/`, except the
   syntax-highlighting palette in `CodeEditorView.qml`, block accents in
   `RobotModels.js` (and the two the Home carousel repeats) and the material
   colours in generated rigs under `content/view3d/rigs/` (all data, not
   styling). Corner radii go through `Theme.radius*` too (all 0: see
   **The look**).

7. **Every mutation goes through `MovementPlan`,** which revalidates, bumps
   `revision`, and emits `planChanged()` — which is what marks the generated code
   outdated. UI code never has to remember to do any of that.

---

## The look: Galaxy theme

Chosen by the user (2026-11-20). The spec and a web reference implementation
live in `<Galaxy Theme folder>\` (`GALAXY-THEME.md` is the source of truth;
`index.html` + `serve.ps1` is a live "theme lab"). In one line: a dark,
mostly **grey** space scene, **purple only as accent**, **sharp square
corners**, thin **Manrope** type, light that comes **from the cursor**.

* **Tokens** are the spec's hex column, in `Theme.qml` under the old names
  (`accent` = accent-strong, `accentBright` = accent, …). Surfaces are
  **glass** (white at 5–9 %), so the starfield shows through. Hence
  `Theme.blend()` is a real "over" composite; the old RGB mix pulled every
  tint on glass towards white. Use `surfaceSolid` where something must
  hide what is behind it (the robot dialog). Never `fade(Theme.surface…)`:
  that makes white glass, not dark glass.
* **Type:** Manrope ships in `content/fonts` (OFL; the licence goes into the
  release resources with it). Weights come from `Theme.weight*`: Light for
  text, ExtraLight for display headings, Medium / DemiBold only for small
  labels. Monospace stays Consolas. Panel titles are spaced capitals.
* **Effects** (`content/common/galaxy/`), each a measured stand-in for the
  web engine:
  * `GalaxyBackground` (behind everything): the nebula band and steady
    stars painted once per size into Canvases with the spec's seeded
    generator (seed 7), twinkle and rising dust as particles, the vignette,
    the 50 px cursor light, and parallax against a smoothed pointer.
  * `FireflyLayer` (z 500, no input) owns one particle system;
    `FireflyEmitter` inside an item makes fireflies on its edge. Emitters
    register a weight in `AppState.fireflyWeight` and share a **fixed
    total** (~40 alive), like the spec's weighted pick. Emitters can live
    anywhere in the tree; particles land in the right place (verified).
  * `SpotLight`: edge glow and inner light near the cursor. It does nothing
    (a Loader is off) unless the cursor is within 200 px.
  * `GlowShadow`: the cursor shadow and the purple under-glow. A blurred
    caster with the item's own rectangle cut out by an inverted mask: like
    a CSS box-shadow, it never darkens the glass it belongs to.
  * The pointer comes from a passive `HoverHandler` in `MainShell`, published
    as `AppState.pointerX/Y/Inside`.
* Things that bit: the particle painter's `alpha` and a translucent
  `color` did **not** dim the bright `fuzzydot` sprite; item `opacity` does.
  Properties named `top`/`bottom`/`left`/`right` clash with `Item`'s anchor
  lines (FINAL). The 3D scene uses `SceneEnvironment.Transparent` so the
  arm floats in the starfield, and its floor uses an opaque colour (a glass
  colour on a material comes out white).
* **Cost:** the sky animates continuously, about 20 % of one core while idle
  (measured on Home). Not done from the spec: `prefers-reduced-motion`
  (Qt exposes no such setting to QML) and the backdrop blur behind glass.

---

## Tool moves

Six palette blocks — Up, Down, Left, Right, Forward, Back — that move the
**tool point** a distance in millimetres in a **straight line**, keeping the
tool's tilt. Block role `"move"`, fields `direction` and `distance`, `jointId`
empty. Available on any model with a `kinematics` entry (Dragon-Arm One).

Decided by the user (2026-11-12) — do not revisit without asking:

* **Robot frame.** X forward (where Axis-1 0° faces), Y to the robot's own
  left, Z up, origin on the table under the base axis. Directions do not turn
  with the base, so forward / right / back / left draws a true square.
* **Straight line**, not joint-interpolated. Running each axis angle-to-angle
  bows the tool 7 mm off a 100 mm line; that was the first version and was
  rejected.
* **Relative to the planned pose.** The sketch stores absolute joint targets
  solved from the Plan start pose. If the arm powers up elsewhere, the first
  move blends from the measured angles to the planned end (`lead` in
  `planFor()`); it does not travel "50 mm from wherever it is".

How it works:

* **Geometry** is `model.kinematics`: base yaw plus three parallel pitch
  joints (`type: "yawPitch3"`), 250 / 200 / 81 mm links, shoulder 125 mm up,
  10 mm from the J5 pivot to the claws' face. All from the CAD pivots in
  `rig.json`; the links' sideways offsets cancel (−49 + 19 + 30), so the tool
  sits in the plane through the base axis and the IK is closed-form.
  `Kinematics.rigAngle()` is the single axis-angle → CAD-angle mapping, shared
  with the 3D view, so encoder offsets move the maths and the model together.
* **`Kinematics.solveMove()`** walks the line in 64 steps, each solved from
  the one before (same elbow side, no whole-turn jumps), and fails with a
  reason if ANY step is unreachable, hits an axis limit, or passes within
  10 mm of the base axis. It keeps every 4th step: 17 angles per axis, the
  axis's **path**.
* **`PlanMath.build()`** is one chronological pass over all blocks (it used
  to be one pass per joint) because a move starts from every axis's commanded
  angle. A move becomes one segment per driven axis, all with the same start,
  duration and ramp, each carrying its `path`. Up/Down drive Axis-2…4;
  horizontal moves also drive Axis-1. That is what the timeline block covers.
* **A path segment's angle is `pathAngle(path, applyProfile(progress))`**: the
  S-curve says how far along the line the tool is, the spline says what angle
  that takes. So the *tool* ramps along the line. Speed and acceleration are
  measured (`pathUnitPeaks()`), not derived from the from/to formula, and
  cached on the segment — measuring is the slow part of a revalidation
  (~2 ms per move block).
* **The sketch** gets a `MOVE_PATHS` table and a `path` column in
  `MOVE_PLAN`; `planFor()` follows the spline and feeds its slope forward.
  Nothing else in the controller changed.
* **Unreachable moves are errors, never shortened** (invariant 4). A new
  block opens at 50 mm, or 25 / 10 if there is no room.
* **Tool below the table is a warning**, swept over the whole plan for every
  kind of block (`checkToolFloor`, `kinematics.floorMm`). A warning because
  the model knows only the bare flange and assumes the base stands on the
  surface below it.
* **UI:** `MoveChip` in the palette; tool-move blocks are drawn in an overlay
  in `TimelinePanel` (not in a track) spanning their lanes, using the same
  `TimelineBlock`; a tool move dropped on any of its lanes covers all of them.
  `MovementPlan.startAngleOf()` / `effectiveDuration()` read the validated
  timeline, which is why `addBlock()` revalidates before choosing a target.

Simulated result (2026-11-12, up 100 / left 80 / forward 60 mm, 0.4° backlash,
0.3° encoder noise, one DIR inverted): tool within 1–2 mm of each line — the
floor set by 0.2° steps and the backlash — final position 1 mm off, zero
reversals while holding. 15 lost steps mid-move: 9 mm excursion, recovered.

Not done: a tool-length field in the UI (irrelevant to up/down/forward at a
fixed heading, a small effect on sideways moves), and tool moves for the
Demo arm (it has no geometry description).

---

## 3D view

A top-level section (sidebar: Home, Blocks › Code, **3D View**) that plays the
plan back on the robot's CAD model, and lets the user **pose** the model with
the mouse to write blocks (see **Posing** below).

* **The pose comes from `MovementPlan.poseAt(t)`**, which runs
  `PlanMath.angleAt()` on the timeline the validator already built. Never
  re-derive motion in the view: then the 3D would show a trajectory nobody
  checked. It starts from each axis's Plan start angle; the real arm starts
  wherever its encoders say.
* **Rigs are generated, never hand-edited.** `tools/export_3d_model.ps1` opens
  `<dragon-arm Blender project>\dragon_arm_trailer.blend` read-only (it has the
  corrected part-to-joint assignments; `dragon_arm_gen1.blend`
  has the joint mounts on the wrong links). It strips the trailer's keyframes,
  resets every J pivot to local Z = 0 (the CAD pose the `viewZeroDeg` values
  assume — the export prints `CAL` lines that must stay J2 64.7 / J3 −110.8 /
  J4 −32.7), skips the render-only `Studio` / `Trailer FX` collections and the
  trailer's gripper (`Gripper (trailer/cad)`, removed at the user's request;
  the arm ends at the J5 claws), assigns every mesh to the J pivot above it,
  merges per (link, material), decimates per part (~980k → ~214k triangles, 6.9 MB)
  and writes `DragonArmOneRig.qml`, whose node
  tree mirrors Blender's: base › J1 › … › J5. Each joint node turns about its
  pivot's local Z (the encoder axis, as `build_scene.py` placed it), in the
  Blender Z-up frame, in millimetres. One `-90°` X rotation stands it up for
  Qt. Re-run cmake after re-exporting.
* **Rig angles are CAD-frame, not axis angles.** `rig.angles[i]` is degrees from
  the pose the CAD was modelled in. The conversion lives in
  `Kinematics.rigAngle()` (shared with the tool-move maths) and in per-joint
  data, so a rig knows nothing about encoders. Joint *i* of the
  model drives rig joint *i*.
* **The model follows the encoder, not the program angle.** The sketch reads
  `angle = (inverted ? 360 − raw : raw) − encoderOffsetDeg`, so the view undoes
  that: `raw = angle + offset` (negated if inverted), then
  `rig = (viewReversed ? −1 : 1) × (raw − viewZeroDeg)`. `viewZeroDeg` is the
  raw reading at the CAD pose. Changing an encoder offset therefore moves the
  model exactly as it moves the real arm — the user relies on this.
* **The 0° pose is defined by the user** (default encoder offsets; increasing
  angles move every axis forward):
  * Axis-1 faces the front of the arm.
  * Axis-2 sits at its back stop.
  * Axis-3 holds the forearm at 90° to the upper arm, bent back.
  * Axis-4 holds the wrist parallel to the upper arm, pointing back down.
  * Axis-5 points at the arm.

  In the fan viewer's convention (`poses.calibrate()` in the Blender project;
  segment directions add up, J2 + J3 + J4) that is J2 134.7°, J3 +90°, J4 +90°.
  The CAD pose is J2 64.7, J3 −110.8, J4 −32.7, giving zeros 70 / 200.8 / 122.7.
  Axis-2's 70 was set by the user against the real arm. The CAD collision
  estimate of 127° (zero 62.3) was 7.7° short. The app's ranges
  confirm it: A3 0–240 = J3 +90…−150, A4 0–180 = J4 +90…−90. Axis-1's zero
  (180) is just its encoder offset. The Axis-1 and Axis-5
  directions turned out correct as defaulted. The user confirmed the whole
  mapping against the real arm on 2026-11-12. The in-app calibration panel
  that was used for this was then removed at their request, so these values
  live only in `RobotModels.js`. Fix any later disagreement there, never in
  the rig.
* Not exported: the drag chains. They are rigid in the CAD and would cut
  through the links while the arm moves.
* Qt 6.8 (Design Studio) loads meshes written by the 6.11 balsam; verified.
  `InfiniteGrid` must be a child of `SceneEnvironment` if it is ever brought
  back (it was too busy against the dark theme).
* A new robot gets a 3D view by: a rig folder under `content/view3d/rigs/`, a
  `view3d` id on the model, `viewZeroDeg`/`viewReversed` on its joints, and one
  line in `RobotViewport`'s `Loader3D` choosing the component.
* Rigs expose `joints` (the turning node of each joint, ids `j1`…`j5`) and
  `linkOf(model)` (`"base"`, `"j1"`…), and every Model is `pickable`. The
  posing needs all three; the exporter writes them.
* **Mouse buttons: left poses, right orbits** (user's request, 2026-11-19:
  orbiting on the left button kept moving the camera when they meant to move
  the arm). `CameraController.qml` is our own: right-drag orbits,
  middle-drag or Shift+right-drag pans, wheel zooms; left-drag orbits too
  only while "Pose with the mouse" is off. It replaces QtQuick3D.Helpers'
  `OrbitCameraController`, which orbits on the left button and only lets that
  be changed from Qt 6.9 (Design Studio runs 6.8). Keep the Helpers import:
  `ProceduralSkyTextureData` comes from it.
* `View3D.camera` must be set explicitly. Rendering works without it (first
  camera found), but `pick()`, `mapFrom3DScene()` and `mapTo3DScene()` do not.

### Posing (animation-style editing)

Requested 2026-11-19: "plan its movement by grabbing its segments or end
effector, which creates movement blocks on the timeline, like in animation
software". Split in two on purpose:

* **`PoseController.qml`** (over the View3D) only turns the mouse into a
  value: an absolute axis angle, or millimetres along a robot axis. It draws
  the gizmos on a Canvas (2D, always on top, any Qt version: no torus or
  arrow geometry needed) and hit-tests them in 2D before `view.pick()`.
* **`View3DModule.qml`** owns the session (`beginPose` / `updatePose` /
  `endPose` / `cancelPose`) and turns values into blocks through
  `MovementPlan`.

What grabbing does:

* **A segment** (turret, upper arm, forearm, wrist) turns the joint it hangs
  from: forward kinematics, an ordinary axis block. **The last segment** (J5)
  is the end effector: drag it, or one of the three arrows (robot X/Y/Z, red/
  green/blue — `Theme.axisX/Y/Z`), and it makes a straight-line **tool move**.
  A free drag of the tool picks the axis whose arrow points most nearly the
  way the mouse went. The **ring** round the tool is Axis-5 roll.
* **Rotation** intersects the mouse ray with the plane the grabbed point
  turns in, so the point stays under the cursor in angle (measured: < 0.25°,
  the 0.5° rounding). Seen edge-on (|axis · ray| < 0.3) that plane is a line,
  so it falls back to "slide": the mouse movement along the grab point's
  screen motion, re-linearised every event. **Translation** takes the point on
  the axis line closest to the mouse ray (measured: 60 px of mouse, 58.9 px of
  tool).
* Measured, not assumed (keep it that way if the rig changes): robot (x, y, z)
  is scene (x, z, −y); a positive rig angle turns right-handed about
  `node.mapDirectionToScene(0, 0, 1)`; the tool point is J5-local (0, 0, −10).

Timing rules, pose-to-pose:

* A drag starts a new step **at the playhead**, or later if one of its axes is
  still busy then (`MovementPlan.freeTimeFor()`), and **the playhead follows
  the step's end** so the model shows the pose being set. The plan is changed
  live, coalesced to one update per event-loop pass, so the 3D always shows
  the validated trajectory, never a preview the validator did not see.
* Dragging the same axis (or the tool along the same line) again **without
  moving the playhead** refines that block instead of adding one.
* **Shift** on a segment: start with the last step, so several axes move
  together. Tool moves always get their own step.
* Dragging back to the start removes the block; Esc restores it; Delete
  removes the selected block. A tool drag that runs out of reach stops at the
  last reachable point and shows the validator's reason; what is on screen
  is what is kept. Angles clamp to the axis range like the slider does.
* New blocks use natural (fastest) duration. A tool move's origin is
  `MovementPlan.commandedPoseAt(start)`, the same pose `PlanMath.build()`
  starts it from, which differs from the pose on screen when another axis
  is still moving.

**Editing on the 3D view's timeline** (`PlaybackPanel.qml`, requested
2026-11-19): every block is a bar on its lane(s), a tool move one bar across
all the lanes it drives. Click selects (the shared `AppState` selection),
drag moves it in time (snapped with `AppState.snap()`, committed on release
like the Blocks timeline), the right edge sets its duration (live), a
double-click returns it to the fastest, and the Delete key or the button next
to the selected block's readout removes it. Clicking an empty lane scrubs and
clears the selection. Things that bit while building it:

* The bars' Repeater model is **block ids only**. An array of objects would
  differ on every revision and rebuild the bar being stretched mid-drag; an
  id array stays equal, so its delegates survive.
* **The time scale is frozen while editing** (`beginEdit()` takes the
  current span, so nothing jumps on the press; it may grow, never shrink).
  Resizing converts pixels with the scale captured at the press.
* `drag.smoothed: false`: the default drops everything moved before the
  drag threshold, which on a quick flick is a lot.
* Moving a block is not checked for overlaps on the way; the validator
  reports them and marks the bar red, as on the Blocks timeline.

Testing, two layers:

* **Maths and session rules:** a `qml.exe` harness that drives
  `PoseController` directly with screen coordinates (scan the view with
  `hitTest()` to find real pixels of each link) and measures tracking.
* **Real mouse input:** `qmltestrunner -import imports -input tst_x.qml` with
  a `TestCase` hosting `MainShell` — presses on the arm pose and do not
  orbit, right-drag orbits, middle / Shift+right pan, the wheel zooms, Esc
  cancels, posing-off hands the left button to the camera. Three traps,
  each of which once looked like "this cannot be tested":
  * `TestCase` is **invisible by default**. Give it `visible: true`, or
    nothing renders, `View3D.pick()` hits nothing and no input arrives.
  * `mouseMove()` sends **no button** unless passed one
    (`mouseMove(item, x, y, delay, Qt.LeftButton)`), so drags look like hover.
  * A `vector3d` property read into a `var` is a **live reference** in Qt 6;
    copy it (`Qt.vector3d(p.x, p.y, p.z)`) before comparing before/after.
  * Send drag events in the coordinates of an item that does **not** move
    (the shell). Coordinates relative to the bar being dragged compound,
    because the bar moves under them.

---

## Patterns worth knowing

- **`MovementPlan.revision`** — plain function calls have no change
  notification, so derived values bind as
  `MovementPlan.revision, MovementPlan.effectiveDuration(id)`. The leading
  comma-expression creates the dependency.

- **`RobotLibrary.currentModel` is a value.** Setters clone → edit → reassign,
  so bindings update. Never mutate it in place.

- **Drag and drop** goes through one invisible proxy in `MainShell.qml` that
  follows the cursor. `AppState.beginPaletteDrag()` / `beginBlockDrag()` set the
  state; `Drag.keys` (`dragonarm.palette` / `dragonarm.block`) decide which
  `DropArea` reacts. Timeline tracks accept palette drags, the trash accepts
  block drags.

- **Sliders** use `Binding { when: !slider.pressed; restoreMode: RestoreNone }`
  so the plan owns the value except while the handle is held.

- **Hidden bindings still evaluate.** A `visible: false` item's bindings run,
  so reading a servo-only property on a stepper joint sprays "cannot assign
  undefined" warnings. `JointConfigRow.qml` reads every field through
  `num()` / `str()` / `flag()` accessors for this reason; do the same in any
  new drive-type-aware UI rather than guarding each binding by hand.

- **Canvas font shorthand needs quoting** for multi-word families:
  `ctx.font = '9px "Segoe UI"'`, not `"9px Segoe UI"` (which silently fails).

- Files are plain `.qml`, not `.ui.qml`. QDS's visual designer only fully
  supports `.ui.qml`, but those forbid JS function bodies, which most of this
  app needs. Edit in Code view; the 2D view still previews.

---

## Extending

**New robot model** — add a factory function in `RobotModels.js`, list it in
`allModels()`. It shows up in the sidebar picker, the home carousel and the
block palette automatically. Nothing in `content/` needs touching.

**New constraint type** — add it to a model's `constraints` array, then handle
its `type` in `Validator.validate()`. Two worked examples exist:
`angleDifference` (a band on `|a − b|`) and `angleOrder` (`a ≤ b`). Both are
thin wrappers around `scanViolationWindows()`, which does the trajectory sweep
and groups violations into time windows — a new rule usually only needs a
one-line `evaluate(a, b)` returning how far outside the legal region the pose is.
If the rule has no tunable numbers, give it `tunable: false` handling in
`RobotModelDialog.qml` (see how `angleOrder` renders without min/max fields).

**New block type** — add a joint with a new `role` to the model, then teach
`PlanMath.targetAngleOf()` how to resolve its target and `BlockInspector.qml`
how to edit it.

**New axis on an existing arm** — just add a joint to the `joints` array.
Palette, timeline lanes, config page and generated enum all follow.

---

## Checking changes

Run the app (above) and watch stderr — QML errors and warnings land there.

For logic changes, a headless harness beats clicking. Write a scratch
`Item { Component.onCompleted: { ... Qt.callLater(Qt.quit) } }` that imports
`DragonArm`, drives `MovementPlan`, prints `MovementPlan.issues` and
`MovementPlan.generateCode()`, then run it with `qml.exe -I imports <file>`.
Keep it out of `content/` so it does not become part of the project.

Worth re-checking after touching the validator: a plan where Axis-2 and Axis-3
*cross* during simultaneous travel (e.g. 60°→140° and 120°→40° together) is
legal at both endpoints and illegal in the middle. It must be rejected.

**After touching the generator, compile what it emits.** The Arduino IDE is the
only place the output is normally exercised, and a name collision with a library
macro is invisible from QML. A stub harness catches it in seconds:

1. Print the sketch from a scratch QML file between markers and extract it.
2. Build stub `Arduino.h` / `Wire.h`, plus an `Adafruit_PWMServoDriver.h` whose
   `#define` lines are copied **verbatim** from the installed library at
   `<Documents>\Arduino\libraries\Adafruit_PWM_Servo_Driver_Library\`
   — that is what makes collisions reproduce.
3. `g++ -fsyntax-only -std=gnu++17 -Wall -Wextra -I stubs -x c++ sketch.cpp`

Use the bundled MinGW at `<Qt>\Tools\mingw1310_64\bin` and put that
directory on `PATH` first, or `g++.exe` exits 1 with no output because it cannot
load its own DLLs. For the stepper sketch, compile twice: as-is (R4/Q path) and
with `-DARDUINO_ARCH_AVR` (10-bit fallback).

**After touching the stepper controller, RUN it, don't just compile it.** A
host-side simulation compiles the generated sketch unchanged (`#include
"stepper.cpp"`) against a fake Arduino. `micros()`/`millis()` advance a
simulated clock, STEP/DIR edges move simulated motors, and `analogRead()`
returns a simulated encoder. Model the hostile cases:

* one axis with DIR physically inverted, which the probe must discover
* 0.4° of backlash between motor and output
* 0.3° of encoder noise
* a burst of lost steps mid-move

Then check:

* the final error is inside the deadband
* lost steps are recovered smoothly, not in a jump
* holding produces zero direction reversals (no dither)
* step intervals during cruise carry no bursts

For tool moves there is a second harness that also checks the *tool*: it
reads reference poses printed by the app (`MovementPlan.poseAt()` every
37 ms), asserts the sketch's `planFor()` returns the same angles and that its
feedforward speed is the derivative of them, then runs the plan and measures
how far the simulated tool strays from each planned line. Start the simulated
arm slightly off the Plan start pose so the first-move blend is exercised.

The reference run (2026-11-09): Axis-3 from 120° to 30° with 3° of steps lost
at t = 3 s. Tracking error was ~0.3° steady, the loss recovered in ~1.2 s, the
axis ended 0.2° off target, and it held with 0 reversals.

---

## Releasing

Put `<Qt>\Tools\mingw1310_64\bin` and `<Qt>\Tools\Ninja` on
`PATH` first, then:

```bash
cmake -S packaging -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="<Qt>/6.11.2/mingw_64"
```

```bash
cmake --build build
```

Copy `build\SpaceDragon.exe` into an empty staging folder, then fill that
folder with the Qt runtime:

```bash
windeployqt --release --no-translations --no-opengl-sw --compiler-runtime --qmldir "<project folder>" stage\SpaceDragon.exe
```

`--qmldir` is required: the QML is compiled into the binary, so windeployqt
cannot discover the imports by scanning the .exe alone. Delete
`stage\qmltooling` afterwards — it is the QML debug server, not release code.

Finally the installer. Inno Setup 6 is installed per-user at
`%LOCALAPPDATA%\Programs\Inno Setup 6`:

```bash
ISCC.exe /DDeployDir="<stage folder>" /DOutDir="<output folder>" /DAppVersion=1.0 packaging\installer.iss
```

Result before the 3D view: ~15 MB setup, ~56 MB installed, per-user install
with no admin prompt. Qt Quick 3D and the rig add ~40 MB installed (~96 MB
staged, measured 2026-11-12); windeployqt picks Quick3D up through `--qmldir`.

**Verify a release by installing it, not just by compiling.** Silent-install to
a scratch folder (`/VERYSILENT /CURRENTUSER /NOICONS /DIR=...`), run the
installed exe **with a minimal `PATH`** — that is what actually proves it is
self-contained — then `unins000.exe /VERYSILENT` and confirm both the folder
and the `HKCU\...\Uninstall\{GUID}_is1` key are gone.

Adding new `.qml` files means re-running cmake; the resource list is globbed at
configure time.

Keep the `AppId` GUID in `installer.iss` stable forever — it is how Windows
tells an upgrade from a second parallel install.

### Exporting a clean copy for other people

Ship `content/`, `imports/`, `packaging/`, `tools/`, `DragonArmStudio.qmlproject`,
`qtquickcontrols2.conf`, `README.txt` and a path-sanitised `CLAUDE.md`.

Leave out `DragonArmStudio.qmlproject.qtds` (per-user Design Studio state) and
anything built. This file cites local install paths and the user's name, so
genericise them before handing it to anyone.
