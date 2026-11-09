# V3 Living Waters data model

The addon saves collection state per character in `VibeFishinDB`, using schema version 3. Each resident has a unique saved identifier independent of its visual frame or species.

## Resident fields

- `uid`: persistent resident identity
- `species`: WoW item/species identification
- `name`: stable generated fish name
- `rarity`: virtual rarity tier (does not change WoW item quality)
- `variant`: virtual cosmetic variant
- `personality`: fish behavior bias
- `happiness`, `hunger`, `temperatureExposure`: saved care state
- `lifeStage`: virtual life state
- `friendUid`, `bondScore`: nearby same-species social relationship, if established

The journal records discoveries only from actual catch events, rather than recomputing totals during visual rebuilds. The rendering scheduler runs at a configurable capped rate; slower survival and spatial checks should not be moved into per-frame updates.

V3 intentionally does not migrate legacy v2 fish records. WoW inventory access remains read-only; no inventory deletion is permitted.
