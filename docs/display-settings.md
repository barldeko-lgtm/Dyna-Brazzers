# Display settings

## Ownership

`res://scripts/settings/display_settings.gd` is the single owner of runtime display mode, window resolution, 16:9 content scaling, persistence, the two display rows injected into the startup Settings menu, and the small runtime layout normalization used by the startup Settings and Load screens.

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
- A selected window resolution is treated as the preferred client-area size. If that size plus the operating-system title bar and borders cannot fit inside the monitor's usable desktop area, the actual client area is reduced proportionally so the decorated window, title bar, and close button remain visible.

## Aspect contract

The logical base remains `1366×768` and uses canvas-item scaling.

- Supported 16:9 displays fill the screen.
- Fullscreen displays with a substantially different aspect ratio preserve the game's 16:9 presentation and use black letterbox/pillarbox space rather than stretching UI or world visuals.
- Returning from fullscreen must restore the normal decorated window and reapply the selected preferred window size.
- Window fitting must preserve the selected resolution's aspect ratio.

## Startup-menu presentation

Load screen:

- Autosave, three save slots, and Back use the same top margin, button width, button height, and vertical spacing as the five buttons on the initial menu.
- The informational text area below the load buttons stays hidden and does not reserve layout space.

Settings screen:

- Language, display mode, and resolution use fixed row geometry.
- Their labels use a fixed-width slot with a 10-pixel left inset, so long translations cannot move the option buttons.
- Their option buttons are 20 pixels narrower on the right than the earlier layout.
- The visible selected value is centered across the stone button; the normally reserved dropdown-arrow area must not offset it.
- Long translated labels reduce their font size within a safe range and then clip rather than changing row geometry.
- Music and sound labels share one horizontal row with their corresponding sliders and start at the same left inset as the three labels above.
- Each volume slider keeps its existing allocation but receives 20 pixels of internal space on the left and 30 pixels on the right.
- All settings content except Back is raised by 30 pixels. A dynamically corrected spacer keeps Back at the exact screen position of the bottom button on the initial menu.
- The Settings Back button copies the initial menu's bottom Exit button size, horizontal layout flags, font, colors, and complete button styles.
- Settings labels outside buttons use a black font outline for readability.

## Localization

Display-setting strings live in `res://localization/display_settings.csv` for `ru`, `en`, `fr`, `de`, and `uk`. The generated translation resources are registered alongside the existing UI translations in `project.godot`.
