# Vibe 4.0 — Interface and theme design

## Layout

- **Aquarium:** 52px header, inset glass, 87px bottom control footer. The original camera-responsive water, swimming, fish care and heater controls remain.
- **Fish / Journal drawer:** 302×424 popout, themed header and separator, 254px wide rows, fish rarity stripes and one resident hover flash.
- **Settings:** 454×620, six tabs in a two-row three-column grid. The options pages have an extended content area and a consistent footer.
- **Theme gallery:** eight themed 194×72 cards in a two-column grid. Selection is immediate and saved per character.

## Theme keys

| Key | Display | Direction |
| --- | --- | --- |
| abyss | Abyss | Deep ocean and aqua highlights (default) |
| midnight | Midnight | Dark neutral with blue controls |
| classic | WoW Classic | Blizzard-native dialog artwork, antique gold |
| coral | Coral Reef | Coral warmth and teal water |
| emerald | Emerald Grotto | Deep jade and forest |
| arcane | Arcane | Violet and magic blue |
| frost | Frostbound | Silver/ice blue |
| sunset | Sunken Sunset | Copper and amber |

Implementation: the theme engine and palettes reside on `aquariumController` in `Core/VibeFishin.lua`. It styles registered backdrop frames, buttons, form labels, slider fills, accents and key textures whenever the selected palette changes. Frames are created once; theme switching doesn't create additional animation loops.

The Classic palette uses Blizzard UI textures already present in the client, referenced by path rather than redistributed.

## Testing checklist (WoW Forever interface 16001)

1. Open `/vfish` and switch through all six tabs, including Theme; check no clipping at 720p and 1080p.
2. Change between all eight themes. Verify aquarium, popout, buttons, slider fills and cast UI recolor without reloading.
3. Select WoW Classic. Verify client Blizzard border/background files render correctly on the aquarium and settings frames.
4. Run `/reload`; verify selected theme and existing fish records persist.
5. Hover resident and journal species rows; only the matching fish should flash and stop when moving away.
6. Resize and drag the aquarium, open the popout on either screen side and verify the footer controls do not overlap.
7. Test an actual fishing cast, catch card, bobber transfer, fish landing, feeding, water movement, temperature and journal registration.
8. Recheck low-impact mode on slower hardware.

No visual game-client testing is performed by GitHub Actions. Automated CI validates Lua 5.1 parsing and the packaging and media inventory. This design preserves v3 schema and does not migrate or delete fish data.
