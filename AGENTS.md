# Repository Guidelines

## Project Structure & Module Organization

This is a Godot 4.6 sandbox-building game. `project.godot` defines the main scene, input actions, Jolt physics, and mobile renderer settings. `scenes/main.tscn` is the application entry point. Gameplay code lives in `scripts/`:

- `main.gd`: world generation, blocks, inventory, crafting, UI, survival, and spawning
- `player.gd`: movement, camera, interaction, swimming, and player input
- `animal.gd`: creature models, movement, health, and behavior
- `item_drop.gd`: dropped-item physics and collection

Keep reusable assets in a dedicated folder such as `assets/`; do not place generated resources in `.godot/` under version control.

## Build, Test, and Development Commands

- `godot --path .` — launch the game locally.
- `godot --editor --path .` — open the project in the Godot editor.
- `godot --headless --path . --quit-after 3` — load the project without a window and catch parse/startup errors.
- `git diff --check` — detect whitespace errors before committing.

Use Godot 4.6.x when possible. No export preset is currently committed, so distributable builds must first be configured in the editor.

## Coding Style & Naming Conventions

Follow existing GDScript conventions and `.editorconfig`: tabs for indentation, `snake_case` for functions and variables, `PascalCase` for preloaded script constants, and `UPPER_SNAKE_CASE` for immutable constants. Add explicit types where they clarify engine objects, vectors, arrays, or dictionaries. Keep material indexes synchronized across `MATERIAL_NAMES`, `MATERIAL_COLORS`, inventory arrays, previews, placement, drops, and recipes. Prefer focused helper functions over expanding `main.gd` branches inline.

## Testing Guidelines

There is no automated test framework yet. Every change must pass the headless startup command. Manually verify affected interactions in-game, especially collision, inventory counts, block placement/removal, crafting inputs and outputs, and day/night spawning. If tests are introduced, place them in `tests/` and name files `test_<feature>.gd`.

## Commit & Pull Request Guidelines

Recent commits use short Chinese, action-oriented summaries, for example `加入煤炭火把与照明配方` or `修复挖坑后玩家卡入地下`. Keep each commit scoped to one feature or fix, and commit repository changes after completing and validating them. Pull requests should explain gameplay impact, list verification steps, link relevant issues, and include screenshots or a short recording for visual/UI changes. Never commit `.godot/`, export directories, editor settings, logs, or temporary files covered by `.gitignore`.
