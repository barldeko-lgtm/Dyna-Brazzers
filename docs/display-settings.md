# Display settings

## Ownership

`res://scripts/settings/display_settings.gd` is the single owner of runtime display mode, window resolution, 16:9 content scaling, persistence, and the two display rows injected into the startup Settings menu.

The script is registered as the `DisplaySettings` autoload in `project.godot` and stores its state separately from gameplay saves at:

- `user://display_settings.cfg`

Display settings must not be stored in save slots.

## Supported modes

- Windowed mode is the first-run default.
- Fullscreen mode uses the current monitor's physical resolution without changing its video mode.
- The first-run window resolution is `1366×768`.
- Supported window resolutions are `1366×768`, `1600×900`, and `1920×1080`.
- Manual free-form window resizing is disabled; the Settings list owns the available window sizes.
- The resolution selector is disabled while fullscreen is active because fullscreen uses the monitor size.

## Aspect contract

The logical base remains `1366×768` and uses canvas-item scaling.

- Supported 16:9 displays fill the screen.
- Fullscreen displays with a substantially different aspect ratio preserve the game's 16:9 presentation and use black letterbox/pillarbox space rather than stretching UI or world visuals.
- Returning from fullscreen must restore the normal decorated window and reapply the selected fixed window size.

## Localization

Display-setting strings live in `res://localization/display_settings.csv` for `ru`, `en`, `fr`, `de`, and `uk`. The generated translation resources are registered alongside the existing UI translations in `project.godot`.
