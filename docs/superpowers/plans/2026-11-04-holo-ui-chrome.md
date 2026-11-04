# Holo UI Chrome + Compact Speed Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** replace the pxl button and panel textures with Blender-rendered cobalt holo glass,
and shrink the speed controls to a single row of `[||] [1x] [3x] [5x]`.

**Architecture:**
- A standalone Blender script draws flat emissive geometry (lines, falloff strips, glass fill
  quads). An orthographic camera at 1 unit = 1 px renders it into five transparent PNGs.
- `theme.tres` 9-slices those PNGs with tiled edges and centre, so it's applied game-wide.
- `speed_controls.gd` drives the pressed and "resume" looks from `_update_display` every
  frame.

**Tech Stack:** Blender 5.2 (Cycles, headless), Godot 4 GDScript, and the repo's custom
`run()`/`run_async()` test harness.

**Spec:** `docs\superpowers\specs\2026-11-04-holo-ui-chrome-design.md`

## Global Constraints

- Cobalt palette:

  | Role | Colour |
  |---|---|
  | Accent | `#3f9fff` |
  | Dim accent | `#1a4e8a` |
  | Pressed default | `#eaf6ff` |
  | Text | `#9fd0ff` |

  No magenta anywhere.
- Output file names are unchanged: `assets\sprites\ui\button_{normal,hover,pressed,disabled}.png`
  and `panel_frame.png`. The `ext_resource` paths in `theme.tres` don't change.
- Blender 5.2: `-b --factory-startup`, launched with `&` and not `start` (see
  `art\README.md`).
- Preserve each file's existing line endings. Git Bash `sed -i` strips CRLF, so patch with
  Python `newline=''`.
- Never commit:
  - `.import` churn;
  - the CRLF noise in `project.godot` and `tests\test_campaign_scene_fleet_panel.gd`;
  - `images.jpg*`, `MEMORY.md`, `token-efficient-execution.md`.

  Delete `images.jpg.import` after each Godot warm pass.
- Commands:
  - Test suite:
    `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
  - Warm pass (reimports changed PNGs): the same exe with `--headless --editor --quit --path .`
  - Expected suite result: only the known `test_campaign_long_run_sim` flake (5-6 failures).
- **Before Task 2:** `scenes\ui\speed_controls.tscn` and `tests\test_speed_controls.gd`
  already carry the uncommitted click fix (with `fleet_commander.gd` and
  `test_fleet_commander.gd`). Those four must be committed on their own first, with user
  approval, so Task 2's diff stays clean.

## Review Focus

1. **"||" or "5x" clipped in the compact bar.** Expected: all four labels are fully visible.
   Pinned by the Task 2 fit test plus a screenshot.
2. **Clicking a speed while paused.** Expected: unpauses at that speed, and the hover
   override on the resume button clears. Pinned in Task 2.
3. **Space toggles pause.** Expected: the pause button's pressed look follows, not just the
   tree. Pinned in Task 2.
4. **Tall or wide panels such as the trade panel.** Expected: scanlines and borders tile
   seamlessly, with no smear or seam at the 9-slice joins. The Task 1 test pins the tile
   modes. Verify by screenshot.
5. **Disabled buttons and body text in campaign panels over the map.** Expected: readable.
   This is a screenshot check in Task 2, and `--panel-alpha` is the knob.

---

### Task 1: Holo texture generator, rendered textures and theme

**Files:**
- Create: `art\blender\holo_ui.py`
- Replace (re-render): `assets\sprites\ui\button_normal.png`, `button_hover.png`,
  `button_pressed.png`, `button_disabled.png`, `panel_frame.png`
- Modify: `assets\ui\theme.tres`, `art\README.md`, `tests\run_tests.gd` (register the test)
- Test: `tests\test_theme.gd` (new, sync `static func run() -> Array[String]`)

**Interfaces:**
- Produces:
  - The PNG sizes and 9-slice margins below. Task 2 relies on the button content margins for
    the bar height.
  - CLI: `holo_ui.py -- --out-dir <dir> [--pressed-color #eaf6ff] [--panel-alpha 0.8] [--samples 16] [--verbose]`

Texture layout. These are starting values; the spec leaves the exact px to the builder, but
keep the divisibility:

| Texture | Size | texture_margin (all sides) | Tiled centre |
|---|---|---|---|
| `button_*` | 24x24 | 6 | 12x12, divisible by the 6 px dash period |
| `panel_frame` | 66x66 | 15 | 36x36, divisible by the 3 px scanline pitch |

- **Button outline:** 1 px, inset 3 px from the edge. Hover and pressed glow falloff is 3 px
  each side of the line, alpha about 0.6 down to 0.
- **Panel:** 1 px border inset 4 px with a 3-4 px glow. Corner L-brackets are 2 px thick and
  12 px long, fully inside the 15 px margin. The glass fill is dark navy (about `#050c18`) at
  `--panel-alpha`. Scanlines are 1 px rows every 3 px, slightly lighter (cobalt at about 6%).
- **Button states:**

  | State | Glass fill | Outline and glow |
  |---|---|---|
  | normal | navy at about 0.35 alpha | `#1a4e8a` outline, no glow |
  | hover | same as normal | `#3f9fff` outline plus glow |
  | pressed | `--pressed-color` at about 0.4 alpha | `--pressed-color` outline plus glow |
  | disabled | same as normal | 3 px on / 3 px off dashes of `#1a4e8a` at about 0.6 alpha |

Render setup (decided):
- Cycles, `film_transparent = True`.
- **`view_settings.view_transform = "Standard"`.** The default AgX shifts emissive colours
  off the palette hex.
- Emission strength 1.0 with `hex_lin` colours, so the output px equals the hex.
- `cycles.use_denoising = False` and `cycles.filter_width` at its minimum, so 1 px lines stay
  crisp.
- Geometry snapped to whole px.
- Partial alpha = `ShaderNodeMixShader(Transparent BSDF, Emission)` with the fac at the
  desired alpha.
- Copy `hex_lin` from `kitbash_corvette.py`. Don't import it, because the script is
  standalone.

- [ ] **Step 1: Write `tests\test_theme.gd` (failing)**

  `run()` loads `res://assets/ui/theme.tres`. For each of `Panel/panel` and
  `Button/{normal,hover,pressed,disabled}`, it gets the `StyleBoxTexture` and appends a
  failure unless all of these hold:
  - the texture is non-null;
  - `texture_margin_left + texture_margin_right < texture.get_width()`, and the same for
    top + bottom against the height;
  - `axis_stretch_horizontal == StyleBoxTexture.AXIS_STRETCH_MODE_TILE` and
    `axis_stretch_vertical == StyleBoxTexture.AXIS_STRETCH_MODE_TILE`.

  It also checks these colours, with `is_equal_approx`:
  - Button `font_color` is `Color("#9fd0ff")`;
  - `font_hover_color`, `font_pressed_color` and `font_hover_pressed_color` are
    `Color.WHITE`;
  - `font_disabled_color` is `Color("#1a4e8a")`;
  - Label `font_color` is `Color("#9fd0ff")`.

  Register it in the `test_scripts` array in `tests\run_tests.gd`.

- [ ] **Step 2: Run the suite and check it fails**

  Expected: `test_theme.gd` FAILs on axis_stretch and the colours. If the constant
  `AXIS_STRETCH_MODE_TILE` fails to parse, the LOW CONFIDENCE names in the spec are wrong.
  Look them up with `ClassDB` or the docs, then fix both the test and the theme.

- [ ] **Step 3: Write `art\blender\holo_ui.py`**

  Functions:
  - `parse_args()`
  - `setup_scene(width: int, height: int, samples: int)`
  - `build_panel(alpha: float)`
  - `build_button(state: str, pressed_hex: str)`, where state is in
    `("normal", "hover", "pressed", "disabled")`
  - `render(out_path: str)`
  - `main()`, which clears the scene between textures and logs per-texture timing under
    `--verbose`

  Match the logging/argparse style of `kitbash_freighter.py`.

- [ ] **Step 4: Render and inspect**

  ```powershell
  cd art\blender; New-Item -ItemType Directory -Force "$env:TEMP\holo_ui" | Out-Null
  & "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python holo_ui.py -- --out-dir "$env:TEMP\holo_ui" --verbose
  ```

  Expected: five PNGs at the sizes above. View each composited on `#05050a` and on
  `#808080`, using a throwaway HTML page in the scratchpad or the Read tool. On mid-grey,
  the glow must stay visible as partial alpha, not drop to nothing. The colours must match
  the palette hex. Copy the five PNGs into `assets\sprites\ui\`.

- [ ] **Step 5: Update `assets\ui\theme.tres`**

  For every StyleBoxTexture:
  - set the margins from the table;
  - set `axis_stretch_horizontal = 1` and `axis_stretch_vertical = 1` (TILE).

  Button styleboxes:
  - `content_margin_left/right = 8`
  - `content_margin_top/bottom = 3`

  Panel stylebox: `content_margin_* = 8`, so padding stays close to the old 7.

  Font colours as in Step 1. Keep the existing `focus` -> hover and `hover_pressed` ->
  pressed reuse.

- [ ] **Step 6: Warm pass, then run the suite**

  Expected: `test_theme.gd` passes, and only the long_run_sim flake remains. Delete
  `images.jpg.import`.

- [ ] **Step 7: Update `art\README.md`**

  Add a "Blender holo UI" section with the run command and flags. Note that
  `art\src\ui_chrome.px.js` is retired, because the UI PNGs now come from `holo_ui.py`.
  Commodity icons are still pxl.

- [ ] **Step 8: Commit**

  ```powershell
  git add art/blender/holo_ui.py art/README.md assets/sprites/ui/*.png assets/ui/theme.tres tests/test_theme.gd tests/run_tests.gd
  git commit -m "Render cobalt holo UI chrome in Blender and retheme"
  ```

  Don't add the `assets/sprites/ui/*.png.import` files.

---

### Task 2: Compact speed bar (layout A)

**Files:**
- Modify: `scenes\ui\speed_controls.tscn`, `scripts\ui\speed_controls.gd`
- Test: `tests\test_speed_controls.gd`

**Interfaces:**
- Consumes: the Task 1 Button content margins (8/3), so a button is about 29 px tall at the
  default font.
- Produces: the node paths `Background`, `Row/PauseButton`, `Row/Speed1xButton`,
  `Row/Speed3xButton` and `Row/Speed5xButton`. `Layout`, `SpeedRow` and `PausedLabel` are
  removed.

Scene (decided):
- **Root `SpeedControls`:** `Control`, `mouse_filter = 2`. Keep its right edge at
  `offset_right = 1115.0`, with `offset_top = 10.0`. Set width and height to fit the row:
  - width: 4 px padding + 4 buttons x 30 + 3 gaps x 2 + 4 px padding, about 134;
  - height: about 37. Set the exact figure from the fit test or the screenshot.
- **`Background`:** `Panel`, full root rect, default `MOUSE_FILTER_STOP` (no override).
- **`Row`:** `HBoxContainer` at a 4 px inset, `separation = 2`, `mouse_filter = 2`.
- **Buttons, in order:** `PauseButton` (text `||`), then `Speed1xButton`, `Speed3xButton`,
  `Speed5xButton`. All have `toggle_mode = true`, `focus_mode = 0` and
  `custom_minimum_size.x = 30`.
- **Drop the `ButtonGroup`.** `_update_display` already sets every button's state each
  frame, and the group's `allow_unpress = false` would fight clearing the resume button
  while paused.

- [ ] **Step 1: Rewrite `tests\test_speed_controls.gd` against the new paths (failing)**

  Keep:
  - the default checks (time_scale 1, unpaused);
  - the Background `MOUSE_FILTER_STOP` check;
  - the 3x/5x/pause/space checks.

  Replace the PausedLabel assertion and add the following, after pressing 5x and then
  pause, followed by `await tree.process_frame`:
  - `pause_button.button_pressed` is true;
  - `speed_5x.button_pressed` is false;
  - `speed_5x.has_theme_stylebox_override("normal")` is true;
  - `speed_1x.has_theme_stylebox_override("normal")` is false.

  Then emit `speed_3x.pressed` and `await tree.process_frame`, and check:
  - `tree.paused` is false and time_scale is 3.0;
  - `speed_3x.button_pressed` is true;
  - `pause_button.button_pressed` is false;
  - `speed_5x.has_theme_stylebox_override("normal")` is false.

  Space path: send a space event, `await tree.process_frame`, then check
  `pause_button.button_pressed` is true.

  Fit check: `row.position + row.get_combined_minimum_size()` must be within
  `background.size` on both axes.

- [ ] **Step 2: Run the suite and check it fails** (node paths missing).

- [ ] **Step 3: Restructure `scenes\ui\speed_controls.tscn` as above.**

- [ ] **Step 4: Update `scripts\ui\speed_controls.gd`**

  - Update the `@onready` paths and remove `paused_label`.
  - In `_update_display()`, with `paused := get_tree().paused`:
    - `pause_button.set_pressed_no_signal(paused)`;
    - for each speed button, with `active := is_equal_approx(Engine.time_scale, s)`, call
      `set_pressed_no_signal(active and not paused)`;
    - if `active and paused`, use
      `add_theme_stylebox_override("normal", get_theme_stylebox("hover", "Button"))`;
    - otherwise use `remove_theme_stylebox_override("normal")`.
  - Leave the `_respawn_pending`, Space, `PROCESS_MODE_ALWAYS` and `_ready` reset behaviour
    unchanged.

- [ ] **Step 5: Run the suite and check it passes.** Only the long_run_sim flake should
  remain.

- [ ] **Step 6: Take in-engine screenshots**

  Use a throwaway non-headless `--script` in the scratchpad that saves
  `root.get_viewport().get_texture().get_image().save_png()`, run via `Start-Process -Wait`.
  Don't commit it. Capture:
  - the combat HUD running at 3x;
  - the combat HUD paused;
  - the campaign trade panel, with a disabled button visible if possible.

  Check:
  - no clipped labels;
  - seamless scanlines and borders;
  - text that reads over the map.

  Fix sizes in the `.tscn` if needed. Show the screenshots to the user.

- [ ] **Step 7: Commit**

  ```powershell
  git add scenes/ui/speed_controls.tscn scripts/ui/speed_controls.gd tests/test_speed_controls.gd
  git commit -m "Compact single-row speed bar with lit pause button"
  ```
