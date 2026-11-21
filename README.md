# SpaceDragon Robot Programmer

Visual, block-based movement programming for servo robot arms, with automatic
Arduino code generation.

Built as a Qt Design Studio (Community Edition) QML project — no C++, no build
step.

## Opening the project

**Qt Design Studio** — open `DragonArmStudio.qmlproject`.

**Command line**

```bash
& "<Qt>\6.11.2\mingw_64\bin\qml.exe" -I imports content/App.qml
```

The look is the Galaxy theme: a grey starfield with a purple accent, glass
panels with sharp corners, Manrope type (bundled, SIL Open Font License, see
`content/fonts/OFL.txt`), fireflies along the edges, and light that follows
the cursor.

## What it does

**Home** — robot and project carousel, editable welcome notes, artwork slots.

**Blocks** — the workspace:

* Palette of the four Dragon-Arm commands: Axis-1, Axis-2, Axis-3, Gripper.
* Drag a block onto a timeline lane, or click it to append.
* Select a block to set its **absolute** target angle, duration and start time
  with paired slider + numeric input.
* Dragon-Arm One also has six **tool moves**: Up, Down, Left, Right, Forward,
  Back. Each moves the tool a set distance in millimetres in a straight line,
  from wherever it is when the block starts, keeping the tool's tilt.
  Directions are the robot's own (forward is where Axis-1 0° faces). On the
  timeline a tool move covers every axis lane it drives, and shows the angle
  each of those axes ends on. A move the arm cannot make is reported, not
  shortened.
* Timeline with adjustable zoom, snapping, scrolling, drag-to-move and
  drag-the-edge-to-resize. Blocks on different lanes at the same position run
  **simultaneously**; overlapping start times run **overlapped**.
* Live validation of the whole plan, with the offending blocks highlighted.
* Trash bin: drag a block up to it to delete (or press Delete).

**Code** — the generated Arduino sketch, syntax highlighted, with one-click
copy and an indicator showing whether it still matches the timeline.

**3D View** — plays the Blocks timeline back on the robot's 3D model
(Dragon-Arm One). Play/pause (Space), restart, loop, 0.25×–2× speed, a
per-axis lane overview and a scrub slider. **Right-drag to orbit**, middle-drag
(or Shift+right-drag) to pan, wheel to zoom. The left button is for posing.

You can also **pose the model** there, as in animation software, and it writes
the blocks for you:

* drag a segment (turret, upper arm, forearm, wrist) to turn its axis;
* drag the tool, or one of its forward / left / up arrows, to move it in a
  straight line;
* drag the ring round the tool to roll Axis-5.

Each drag adds a step at the playhead and moves the playhead to its end, so
pose after pose builds a sequence. Drag the same thing again to refine the
step, hold Shift to move a segment together with the previous step, Esc to
cancel, Delete to remove the selected block. Untick "Pose with the mouse" to
only watch; the left button then orbits as well.

The timeline under the model is editable too: drag a block to move it in
time, drag its right edge to change its duration, double-click it to make it
as fast as the axes allow, and remove the selected one with Delete or the
Delete button. A tool move is one block across all the axes it drives. The model follows the encoder offsets, so it stays in step
with the real arm when they change. To rebuild the model after a CAD change, run
`tools/export_3d_model.ps1` (needs Blender).

**Robot model** (bottom of the sidebar) — model selection plus the full hardware
configuration: PCA9685 channel per servo, I²C address, PWM frequency, per-servo
pulse-width calibration, mechanical limits, home positions, mounting direction,
and the mechanical constraint limits.

## Dragon-Arm Demo hardware

| | |
| --- | --- |
| Controller | Arduino Uno |
| PWM driver | PCA9685, I²C, default `0x40` |
| Servos | MG996R, 0°–180° nominal |
| Channels | Axis-1 → 0, Axis-2 → 1, Axis-3 → 2, Gripper → 3 (all reconfigurable) |
| Gripper | Grip = 0°, Release = 90° |
| Mounting | Axis-3 is mirrored (`inverted`) by default |

### Startup behaviour

Homing is **off** by default: no channel is driven until a servo's first
movement is due, so the arm keeps whatever pose it powered up in. Turn it on in
the robot model if you want the arm driven to its start angles first.

A non-blocking **start delay** (default 1000 ms) runs before the timeline. With
homing on it doubles as the settling time.

The per-servo *start angle* is still what the planner validates against — an
open-loop servo cannot report where it actually is, so the plan needs a stated
reference pose.

### Mechanical constraints

Two rules, both configurable in the robot model:

```
40° ≤ |Axis-2 − Axis-3| ≤ 140°     spread
Axis-2 ≤ Axis-3                    ordering
```

Together they mean `40° ≤ Axis-3 − Axis-2 ≤ 140°`.

Both are checked across the **entire** movement plan — including while both
servos are travelling — not just at the target angles. Two blocks that are each
legal on their own can still sweep the arm through an illegal pose; the app
finds the time window, names the angles, says what range the offending axis
needs to be in, and refuses to emit executable code until it is fixed.

## Generated code

The sketch uses `Adafruit_PWMServoDriver` (Arduino Library Manager: *Adafruit
PWM Servo Driver*). It:

* initialises the PCA9685 over I²C at the configured address and frequency,
* converts absolute angles to pulse widths using each servo's own calibration,
* stores the timeline as a table of `(servo, startMs, durationMs, fromAngle,
  toAngle)` rows,
* interpolates every active row on a `millis()` tick and writes one angle per
  servo — so servos move simultaneously and none waits for another,
* contains no `delay()` anywhere.

### Smoothness

Analog servos jerk when a movement starts and stops abruptly, and a long slow
travel is where it shows worst. Three things in the generated sketch address it:

* **Eased motion** (`shapeProgress()`, smoothstep) ramps speed up and back down
  instead of stepping straight to full rate at both ends. The planner validates
  against the identical curve. Switch to `Linear` in the robot model if you
  prefer constant speed.
* **A forced final write** lands exactly on the target when a sequence ends.
* **A hold refresh** (default 1 s) re-sends the current target periodically, so
  one dropped I²C write cannot leave a servo parked at a stale position.

If servos still buzz or the travel range looks wrong, the usual culprit is
`PWM_DRIVER_OSCILLATOR_HZ`. The PCA9685 datasheet says 25 MHz; real boards
measure 26–27 MHz, and every pulse width scales with it. Measure the actual
output frequency and correct the value in the robot model.

`RELEASE_AFTER_SEQUENCE` (off by default) cuts PWM when the sequence ends — that
stops idle buzzing, at the cost of the arm no longer holding its final pose.

## Adding artwork

See [`content/images/README.md`](content/images/README.md). Every placeholder in
the UI prints the path it is waiting for.

## Project layout

See [`CLAUDE.md`](CLAUDE.md) for the architecture, conventions and extension
points.

## License

MIT, see [`LICENSE`](LICENSE). The bundled Manrope font is under the SIL Open
Font License (`content/fonts/OFL.txt`).
