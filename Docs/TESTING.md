# VibeFishin release testing checklist

## Static checks

1. Compile `Core/VibeFishin.lua` with a Lua 5.x parser before release (this build was parsed using `texlua`/Lua `loadfile`).
2. Check all relative paths in `VibeFishin.toc` and confirm every `Interface\AddOns\VibeFishin\Media` texture file exists.
3. Verify `VibeFishinDB` remains the per-character saved-variable name and the folder and `.toc` names match.
4. Validate ZIP integrity and inspect that it contains `Core`, `Media`, the `.toc`, `README.md` and `Docs`.

## In-game tests (required before public release)

- `/reload`: no Lua errors; confirm the addon title and author in AddOns.
- `/vfish on`, `/vfish off`, `/vfish timer`: timer, cast detection and bait reminder.
- `/vfish preview` while aquarium is visible: fish icon travels to **top** of glass; white/blue splash and outward overflow emit without nil-function errors.
- `/vfish chesttest` and `/vfish refresh`: randomized straight-down chests, impact sand/bubbles; previous fish positions preserved where applicable.
- Hover roster entries, feed fish and confirm that hunger and happiness settings survive `/reload`.
- Open Cooking, scan learned recipes and verify matching Cooking badges.
- Test sustained cold and hot water exposure: fish die after sufficient exposure, float to the surface, turn into skeletons after five minutes, and never affect bag items. Return temperature to the safe range before the fatal threshold to confirm exposure recovers.
- Resize to minimum and maximum desired size; verify temperature and hunger text remain inside the tank footer.
- Confirm frame rates with crowded tanks; unlimited fish may have a significant CPU cost.

## Known limitations

Mocked Lua frames cannot validate the client’s actual event permission model, client item metadata availability, live texture rendering or real fishing cast timings. Tests performed outside WoW are necessary but not sufficient.

## v1.2.2 performance regression checks

- Profile CPU with five fish and with 150+ fish, with the same camera position and UI state.
- Repeat with aquarium hidden; cast timer should still respond to fishing casts.
- Confirm feed pellets, death by hunger/temperature, skeleton transformation and name roster remain correct.
- Toggle Low-impact mode and change animation FPS in the Performance tab.
- Confirm the unlimited-fish setting is still present and resident count does not silently cap.
