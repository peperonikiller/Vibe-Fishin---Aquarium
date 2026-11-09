# VibeFishin developer architecture

## Official WoW addon loading conventions

The game locates `VibeFishin/VibeFishin.toc` and loads its Lua/XML files in listed order. The `.toc` header declares supported interface (`16001`), metadata (`Title`, `Notes`, `Author`, `Version`), and `SavedVariablesPerCharacter`. Do not rename the **folder** or `.toc` independently. Media textures load by file path, so they are not `.toc` entries.

Sources: https://warcraft.wiki.gg/wiki/TOC_format and https://warcraft.wiki.gg/wiki/AddOn_loading_process

## Runtime layout

- `Core/VibeFishin.lua`: ordered runtime. This file intentionally remains in one Lua lexical scope so shared local references and client callback ordering are preserved.
- `Media/`: in-package texture assets. Paths in Lua use `Interface\AddOns\VibeFishin\Media\...`.
- `README.md`: installation, attribution and credits.
- `Docs/TESTING.md`: reproducible release checklist.

## Data ownership and safe actions

`VibeFishinDB` remains a per-character saved variable for existing installations. Internal aliases have meaningful names such as `characterSettings`, `aquariumWindow`, `aquariumCanvas`, `aquariumController`, `swimmingFish`, `castTimerWindow` and `overflowDroplets`. Player-chosen settings remain persisted independently of the internal rename. The former `showCookingKnife` setting is migrated once to `showCookingBadges` and the stale key is cleared.

All aquarium-care interactions are virtual. Hunger, temperature stress, and death/skeleton effects modify only saved addon state. No item pickup, deletion, or destruction APIs are called. The inventory-fish display option only reads normal player bags.

## Simulation and visual lifecycle

- Fishing events → `onLoot` → classify a fish, aquatic plant, or treasure → update the aquarium.
- Catch reveal → `startCatchFlight` → `animateCatchFlight` → `splashAt` → `spawnSpill` and `animateSplash`.
- Water motion uses client-exposed character facing; the API does not provide a reliable camera-only angular velocity.
- `repopulateAquarium` preserves existing fish positions when requested and restores dead-fish records.
- `updateFishVisuals` advances movement, feeding, hunger, per-fish thermal exposure, floating carcasses, skeletons, sand and atmospheric effects. The heater simulation gradually changes water temperature; thermal exposure fades under safe conditions.
- Bag fish represent carried inventory; the aquarium does not include banked fish after bag refresh.

## Why some compatibility handling remains

A handful of client API fallbacks still protect against item-cache and Forever API-shape differences. They are active error handling, not dead compatibility branches. Do not remove API safeguards without in-game client evidence and regression tests.

## v1.2.2 simulation scheduler

The single OnUpdate callback gates all expensive work to configurable 10–30 Hz (default 20 Hz). Visual fish movement and bobber updates run at that rate while visible. A spatial grid, recreated at ~5 Hz, holds nearby fish for schooling avoidance; schooling targets are cached between updates. Sand and decorations run at ~10 Hz (5 Hz in Low-impact mode). Survival and thermal simulation run at 1 Hz irrespective of window visibility. The tank hides all visual updates when not shown.
