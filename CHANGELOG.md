# Changelog

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
