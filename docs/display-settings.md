# Display settings

This file is intentionally kept as a compatibility pointer for older links.

Display settings no longer maintain a separate detailed design note because that duplicated information and drifted from the main project documentation.

Canonical locations:

- implemented/player-visible behaviour: `docs/current-state.md` → **UI, display settings, localization, and diagnostics**;
- file paths and ownership: `docs/project-map.md` → **UI, settings, localization, audio, save, and debug**;
- refactor/save/runtime contracts: `docs/dependencies.md` → **UI ownership and display settings**.

The implementation source of truth remains:

- `res://scripts/settings/display_settings.gd`;
- `res://scripts/save/save_system_with_enemy.gd` for the current in-game Settings presentation;
- `res://localization/display_settings.csv`;
- `res://project.godot`.

Do not add pixel-layout notes or a second copy of the display contract here. Update the canonical three working documents when behaviour, ownership, or a fragile invariant changes.
