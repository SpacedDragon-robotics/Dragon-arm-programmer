# Images

Drop artwork here; the placeholders in the UI step aside automatically.

| File | Used by | Suggested size |
| --- | --- | --- |
| `dragon-arm-demo.png` | Home carousel slide for the Dragon-Arm Demo | 900 × 620 |
| `project-01.png` | Home carousel "project" slide | 900 × 620 |
| `home-banner.png` | Home gallery panel (bottom right) | 800 × 400 |
| `logo.png` | Sidebar mark and home branding (`LogoMark`); the website's dragon-head logo, trimmed | 256 × 256 (in use) |
| `appicon.png` | Window icon (same logo; `packaging/spacedragon.ico` is made from it) | 256 × 256 (in use) |

Wiring an image up:

* **Carousel / robot renders** — set `image:` on the model in
  [`imports/DragonArm/RobotModels.js`](../../imports/DragonArm/RobotModels.js),
  e.g. `image: "images/dragon-arm-demo.png"`.
* **Other slots** — set the `source` property of the `PlaceholderArt` item in
  the relevant QML file. Every placeholder prints the path it expects.

Paths are relative to the `content/` directory.
