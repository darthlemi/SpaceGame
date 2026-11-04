# Holo UI chrome + compact speed bar - design

Date: 2026-11-04. Status: draft for approval.

## Intent

The UI chrome (button and panel textures) is still the early pxl pixel art from `72fa583`.
The ships have since moved to Blender kitbash renders with a neon-on-dark-space mood. The
user wants the UI redone in Blender to match that mood. They chose a **cobalt holo glass**
look: a projected HUD of thin glowing lines on dark glass, not physical hardware. They also
want the speed controls (currently a 165x121 panel) shrunk to a compact single row.

Success: every Panel and Button in the game picks up the new look through the global theme
without per-scene edits. The speed bar is about 140x30 px and still fully works. The
textures are reproducible from a script under `art\blender\`, like the ships.

## Goals

- A Blender script that renders the five theme textures: `button_normal`, `button_hover`,
  `button_pressed`, `button_disabled` and `panel_frame`.
- Update `assets\ui\theme.tres` to the new textures' 9-slice margins and the cobalt font
  colours.
- Compact speed bar: one row `[||] [1x] [3x] [5x]`, mockup A (below).
- Update `art\README.md` with the script and its run command.

## Non-goals

- Commodity icons (`assets\sprites\commodities\*.png`) stay as pxl art.
- Fonts and font sizes are not changed.
- No per-scene layout changes outside `speed_controls.tscn`. Other panels restyle through
  the theme only.
- Ships, bases and VFX are untouched.

## Anti-goals (a failure even if it works)

- Physical hardware chrome: bevels, bolts, gunmetal plates. The user picked holo glass
  over the kitbash-plate style.
- Magenta anywhere. The user rejected it for the pressed state.
- Stretched scanlines or dashes. 9-slice stretching that smears the line pattern looks
  broken.
- Text that's hard to read over the campaign map because the glass is too clear.

## Approved look (from the visual companion)

Mockups: `.superpowers\brainstorm\1387-1793804817\content\cobalt-pressed.html` (option 4)
and `speed-bar.html` (option A).

Palette. Cobalt is the palette's neon blue, from `art\src\palette.px.js`:

| Role | Colour |
|---|---|
| Accent (lines, brackets, hover glow) | `#3f9fff` |
| Dim accent (normal outline) | `#1a4e8a` |
| Pressed ("white-hot") | `#eaf6ff` |
| Text | `#9fd0ff` |

- **Panel:** dark, tinted glass with fine horizontal scanlines. A thin cobalt border with a
  soft inner glow, and brighter L-shaped brackets on the four corners.
- **Button normal:** a thin dim-cobalt outline on near-clear glass.
- **Button hover:** the outline goes full cobalt and glows. The text goes white.
- **Button pressed:** a white-hot fill and glow, about 35-45% fill strength, so white text
  still reads on it.
- **Button disabled:** a dashed, faded dim-cobalt outline.

## Decided by the user

- Holo glass style (B of four directions), cobalt lines (1 of six schemes).
- White-hot pressed state as the **default**. The pressed colour is a script flag, so it
  can change later.
- Speed bar layout A:
  - One row: pause, then 1x, 3x and 5x.
  - While paused, the pause button shows the pressed (white-hot) look.
  - While paused, the speed the game will resume at shows the hover look (bright outline,
    no fill).
  - No separate PAUSED label.
- Built in Blender, next to the ship generators.

## Builder's calls already made (flag if wrong)

1. **Script:** `art\blender\holo_ui.py`. It's standalone, with no import of
   `kitbash_corvette.py`, since none of the hull code applies. Flags:
   - `--out-dir` (required)
   - `--pressed-color` (default `#eaf6ff`)
   - `--panel-alpha` (glass opacity, default about 0.8)
   - `--samples`
   - `--verbose` (timing per texture)

   It writes the five PNGs with transparent backgrounds, under the same file names, so the
   `ext_resource` paths in `theme.tres` don't change.
2. **Glow is built from geometry, not the compositor Glare node.** Each glowing line gets
   soft-edged falloff strips (emission mixed with transparency). Glare on a transparent film
   tends to drop the glow from the alpha channel, and the compositor API changed in
   Blender 5.x. No compositor is needed this way.
3. **Pixel-exact framing:** an orthographic camera with 1 Blender unit per output px, and
   line widths in whole px. That keeps the 1 px lines crisp at these tiny sizes.
4. **Texture sizes and margins:** keep about the current footprint, with buttons around
   56x22 to 56x32 and the panel around 160x100. The 9-slice margins must contain the corner
   brackets and the full glow falloff.
   - `texture_margin_*` and `content_margin_*` are set separately, so the bar's buttons can
     be about 30 px tall at the default font size.
   - The centre and edges tile instead of stretching (`axis_stretch_*` set to tile or
     tile-fit), so scanlines and dashes keep their pitch.
   - [!] LOW CONFIDENCE: the `StyleBoxTexture.axis_stretch_horizontal` and
     `axis_stretch_vertical` property names and enum values. Check them against the
     Godot 4 docs.
5. **Theme colours:**
   - Button: `font_color` `#9fd0ff`, hover/pressed/hover_pressed `#ffffff`, disabled about
     `#1a4e8a`.
   - `Label/colors/font_color` changes to `#9fd0ff` too, so labels match the HUD. This
     affects every label in the game.
   - `focus` keeps reusing the hover stylebox. `hover_pressed` keeps reusing pressed.
6. **Speed bar placement:** the top-right corner stays where it is (right edge x=1115,
   top y=10, viewport 1152x648). The pause button is `toggle_mode` and not in the speed
   `ButtonGroup`. Its pressed state mirrors `get_tree().paused` in `_update_display`.
   - The pause button text is `||`, with no icon texture.
   - The `Background` Panel stays and keeps the default `MOUSE_FILTER_STOP`. The
     click-through fix from earlier today depends on it.
7. **"Resume speed shows hover look while paused":** the implementation is the builder's
   choice. For example, clear the speed button's pressed state while paused and give it the
   theme's hover stylebox as a `normal` override, then restore it on unpause. Apply it from
   `_update_display`, which runs every frame, so it reasserts itself instead of drifting.
   Clicking a speed while paused still unpauses at that speed, as today.
   - Bar fit: four buttons at about 30 px wide, 2 px gaps and about 4 px panel padding
     gives about 140 px. If the texture side margins don't fit, set the button sizes by
     hand, then check that `||` and `5x` don't clip.
8. **`art\src\ui_chrome.px.js`:** left in place, but no longer the source of the shipped UI
   textures. The README says so. It isn't deleted. `commodity_icons.px.js` is untouched.

## Constraints

- Blender 5.2, run headless with `-b --factory-startup` (see `art\README.md`).
- Godot 4 GDScript. Files in this repo are CRLF, and Git Bash `sed -i` strips CRLF, so
  patch with Python `newline=''`.
- Keep the existing behaviour of `scripts\ui\speed_controls.gd`:
  - `_respawn_pending` blocks every input.
  - Space toggles pause.
  - `PROCESS_MODE_ALWAYS`.
  - `_ready` resets time_scale to 1 and unpauses.
- Tests: `tests\test_speed_controls.gd` is the custom `run_async` harness, called from
  `tests\run_tests.gd`.
  - Update its node paths to the new tree. The `Layout` VBox and `PausedLabel` go away.
  - Keep the Background `MOUSE_FILTER_STOP` check.
  - Replace the PAUSED-label assertion with "pause button `button_pressed` while paused".
- The full suite should show only the known `test_campaign_long_run_sim` flake.
- Don't commit the `.import` churn or the CRLF noise in `project.godot` and
  `tests\test_campaign_scene_fleet_panel.gd`. The four uncommitted click-fix files are a
  separate commit.

## Verification

- Render all five textures. View them on a dark backdrop and a mid-grey one to check that
  the alpha and glow survive.
- In-engine screenshots (recipe in `carry_forward.md`: a non-headless `--script` that saves
  the viewport PNG) of:
  - the combat HUD with the speed bar running and paused;
  - one campaign panel with buttons, such as the trade panel.

  Check that the text reads over the map and that there are no smeared scanlines.
- The speed controls test passes, and the suite is otherwise unchanged.

## Left to the builder

- The exact px sizes, line widths, glow falloff width, scanline pitch and bracket length,
  within the look above.
- How the pressed fill is shaded (flat or gently graded).
- Whether the speed bar uses an HBoxContainer directly under the root or keeps one wrapper.
