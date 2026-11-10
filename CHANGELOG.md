# Changelog

## [4.1.0] — Fishing Journal and layout refinement

- Rebuilt Journal as a wide species browser and detail pane with item icons, rarity, lifetime catch totals, variant progress, resident counts and last-caught dates.
- Added dedicated Profile, Awards and Recent tabs, including milestone progress and the latest 40 real fishing catches.
- Corrected Classic UI styling to use Blizzard border artwork only on large windows; small controls use proper flat backdrops instead of distorted button textures.
- Improved contrast by keeping Settings opaque and ensuring the aquarium remains readable while the game world is visible.
- Fixed recycled journal/fish row alignment and removed stale row interactions when changing views.
- Preserved existing v3/v4 collections, care data and settings; recent catch history starts recording after updating.


## [4.0.1] — Interface alignment fixes

- Replaced the cramped two-column Theme gallery with readable full-width theme rows and short descriptions.
- Added a clear selected-theme marker and corrected theme-card spacing on scaled UIs.
- Re-anchored heater controls to the aquarium footer's left edge and aligned actions along its right edge, including after resize.


## [4.0.0] — The Aquarium UI Overhaul

- Rebuilt the aquarium with a branded header, inset glass viewport, dedicated control footer and refined borders.
- Redesigned the wider fish/journal drawer with a header strip, improved spacing, rarity accents and corrected row alignment.
- Reorganized settings into six tabs over two rows, with more spacious content and an interactive Theme gallery.
- Added eight themes: Abyss, Midnight, WoW Classic, Coral Reef, Emerald Grotto, Arcane, Frostbound, and Sunken Sunset.
- WoW Classic uses Blizzard's native dialog artwork; custom themes coordinate windows, buttons, sliders, labels, accents, aquarium water and the catch overlay.
- Theme changes apply immediately and persist per character. The /vfish theme command opens the gallery.
- Existing v3 fish, care stats, journal, achievements and catch animations are retained. No destructive inventory APIs.

## [3.0.4] — Journal fish locator

- Hover a journal species to flash a matching fish currently in the aquarium.
- Hover an individual resident to flash that exact fish icon.
- Highlight automatically clears on hover exit, panel close, or aquarium refresh and runs within the existing animation budget.


## [3.0.3] — Keep the fishing timer visible on catch

- Preserve the complete fishing rod and countdown during the brief gap between channel end and loot.
- Keep the timer visible alongside the bobber transfer until the fish lands in the aquarium.
- Cleanly hide the timer if no catch arrives or the aquarium transfer cannot complete.


## [3.0.2] — Catch bobber handoff

- On fish catches, the timer bobber travels to the catch-preview icon and accompanies it to the aquarium.
- Reuses the existing catch-flight animation update budget; cosmetic only, with no item interactions.
- Bobber disappears upon water impact and resets safely between catches.


## [3.0.1] — Living Waters: roster hotfix and WowUpHub packaging

- Fixed unqualified rarity, variant, and personality table references in the journal and resident tooltips.
- Added a WoW Forever-specific `VibeFishin_Forever.toc` for game-flavor detection by WowUpHub.
- Added an aquarium preview image in `.previews/` and updated the GitHub release package checks.

## [3.0.0] — Living Waters

- Individual saved fish identities with unique IDs, names, rarity, personality, life stage, wellness, and bond scores.
- Cosmetic rarity tiers and persistent collectible variants; WoW items remain unchanged.
- Personality-driven fish movement and nearby same-species friendships.
- Species encyclopedia, discovery history, and eight achievements.
- Continued throttled aquarium animation and spatial lookup optimizations.
- Fresh v3 saved-data schema; v2 resident data is not migrated.

## [2.0.2] — Transparent cast timer

- Removed the filled timer background, tooltip-style border image, and yellow indicator artwork.
- Added a cyan water-level line that sways with the animated bobber.
- Replaced textured cast ripples with minimal colored lines; retained the timer countdown and performance cap.


## [2.0.1] — Feeding reliability

- Pellets remain available for up to two minutes, allowing distant fish more time to reach them in Low-impact mode.
- Inventory updates and aquarium rebuilds no longer discard an active food batch; stale fish claims are cleared.
- Fish already nibbling complete their five-second meal when the feeding window closes.
- Dead fish cannot be revived by late pellet completion.

## [2.0.0] — Release candidate

- Consolidated the v1.2.2 performance scheduler and unlimited-fish aquarium for an installable GitHub release.
- Retained hunger, happiness, and heat/cold death simulation, with no inventory-destructive features.
- Tidied initialisation formatting and prevented redundant catch-flight retries when transfer cannot begin.
- Added consistent release metadata, installation instructions, credits, packaging and automated source/asset checks.

## [1.2.2] — Performance

- Decoupled aquarium simulation from WoW render FPS.
- Added spatially filtered schooling, reduced-frequency decoration updates and a low-impact performance mode.

## [1.2.1] — Aquarium care

- Removed Realism/item-deletion features; added temperature-related fish mortality.

Earlier development releases (0.x–1.2.0) were iterative builds prior to the public 2.0 release.
