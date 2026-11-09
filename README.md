# Vibe - Fishing Aquarium

**Version 3.0.1** · **Author: Pepkilz** · World of Warcraft: Forever (interface `16001`)

A resizable, animated fishing aquarium inside World of Warcraft. Caught fish populate a virtual tank with a resident roster, generated names, feeding, hunger, temperature, happiness, and simulated death. Fish and treasure enter with animated splashes; you can customize water movement, sand, plants, seaweed, crabs, and the heater.

> **Community project:** Not affiliated with or endorsed by Blizzard Entertainment or the World of Warcraft: Forever server team. World of Warcraft trademarks and client interface assets belong to Blizzard Entertainment.

## Installation

1. Download the archive **`VibeFishin-v3.0.1-forever.zip`** from the release page.
2. Extract its **`VibeFishin`** folder into your client's `Interface/AddOns/` directory.
3. Enable **Vibe - Fishing Aquarium** in the AddOns list and use `/reload` if WoW is running.
4. Enter `/vfish` to open options. `/vfish on`, `/vfish off`, and `/vfish toggle` control fishing mode.

**Important:** The directory must remain named `VibeFishin`, because the client loads `VibeFishin.toc`. Existing character settings are retained under `VibeFishinDB`.

### WowUp / WowUpHub

- Official GitHub releases attach an installable ZIP with a single top-level `VibeFishin/` directory; the standard `VibeFishin.toc` and `VibeFishin_Forever.toc` files are immediately inside it.
- The Forever-specific TOC lets WowUpHub identify the correct WoW Forever game version. The release is marked **latest**, not **pre-release**.
- To install directly from GitHub in WowUp, choose **Get Addons → Install from URL** and enter `https://github.com/peperonikiller/Vibe-Fishin---Aquarium`.
- **WowUpHub directory listing requires Hub onboarding:** send the repository URL to a WowUp Discord moderator or Zakrn for review and connection. A proper release alone does not guarantee public Hub listing. See [WowUp Hub documentation](https://wowup.io/guide/wowup/hub).
- WowUpHub also looks for a social preview in GitHub repository settings and optionally uses the `.previews/` folder for screenshots. Use the uploaded aquarium artwork to set the social preview under GitHub **Settings → Social preview**.
- **CurseForge requires separate project approval and distribution.** A GitHub release is not automatically a CurseForge release.

## New in Vibe 3.0 — Living Waters

**A clean v3 aquarium record format.** Each fish is a separate saved character record with
`uid`, `species`, `name`, `rarity`, `variant`, `personality`, `happiness`, `hunger`,
`temperatureExposure`, `lifeStage`, wall-clock feeding/death timestamps, and optional
`friendUid`/`bondScore`. Visual frames are recreated from records on `/reload`,
without re-rolling identity or rarity. Records are saved per character in `VibeFishinDB`.

**Collectibles (simulated, never WoW item modifications):** Common, Uncommon, Rare,
Epic, and Legendary fish. Golden, Albino, Glowing and Giant appearances are rolled
at first capture and persist. The catch card and roster show the virtual rarity and
variant; item quality remains unchanged. Rarity and variant probabilities are
weighted, with Legendary and Glowing especially rare.

**Personalities and relationships:** Curious, Social, Forager, Shy, Lazy and Playful
residents have distinct roaming, schooling, feeding or swimming tendencies.
Residents can form bonds with nearby same-species fish in the existing low-rate
spatial scan. Relationship state is saved and visible in the roster.

**Journal and achievements:** Click **>** on the aquarium and choose **JOURNAL**, or
enter `/vfish journal`. The journal records catches per species, best simulated
rarity, discovered variants and eight milestone achievements. Only actual fishing
loot advances discoveries; refreshing the tank and scanning bags do not.

**Performance:** Fish animation stays capped at the selected 10–30 FPS. School and
relationship logic reuses the 5 Hz spatial index; survival updates at 1 Hz; the
journal does no per-frame calculations. The aquarium still pauses visual work
when hidden.

**Upgrade note:** v3 deliberately uses a new resident database, without migrating
v2 fish records. Settings and older data fields may remain in SavedVariables, but
v3's fish roster and journal begin a new collection. `/vfish reset` clears the
current resident aquarium; the discovery journal remains available separately.
This addon never creates, modifies, destroys, or deletes in-game items.

## New in Vibe 3.0 — Living Waters

**A clean v3 aquarium record format.** Each fish is a separate saved character record with
`uid`, `species`, `name`, `rarity`, `variant`, `personality`, `happiness`, `hunger`,
`temperatureExposure`, `lifeStage`, wall-clock feeding/death timestamps, and optional
`friendUid`/`bondScore`. Visual frames are recreated from records on `/reload`,
without re-rolling identity or rarity. Records are saved per character in `VibeFishinDB`.

**Collectibles (simulated, never WoW item modifications):** Common, Uncommon, Rare,
Epic, and Legendary fish. Golden, Albino, Glowing and Giant appearances are rolled
at first capture and persist. The catch card and roster show the virtual rarity and
variant; item quality remains unchanged. Rarity and variant probabilities are
weighted, with Legendary and Glowing especially rare.

**Personalities and relationships:** Curious, Social, Forager, Shy, Lazy and Playful
residents have distinct roaming, schooling, feeding or swimming tendencies.
Residents can form bonds with nearby same-species fish in the existing low-rate
spatial scan. Relationship state is saved and visible in the roster.

**Journal and achievements:** Click **>** on the aquarium and choose **JOURNAL**, or
enter `/vfish journal`. The journal records catches per species, best simulated
rarity, discovered variants and eight milestone achievements. Only actual fishing
loot advances discoveries; refreshing the tank and scanning bags do not.

**Performance:** Fish animation stays capped at the selected 10–30 FPS. School and
relationship logic reuses the 5 Hz spatial index; survival updates at 1 Hz; the
journal does no per-frame calculations. The aquarium still pauses visual work
when hidden.

**Upgrade note:** v3 deliberately uses a new resident database, without migrating
v2 fish records. Settings and older data fields may remain in SavedVariables, but
v3's fish roster and journal begin a new collection. `/vfish reset` clears the
current resident aquarium; the discovery journal remains available separately.
This addon never creates, modifies, destroys, or deletes in-game items.

## Features

- **Living collection:** Animated fish, per-fish names, school movement, feedable pellets, starvation, happiness and temperature exposure. Dead fish float upside down and become skeletons.
- **Collection modes:** Recent session catches or fish held in bags; inventory scanning is read-only. Nothing is deleted from your WoW inventory.
- **Atmosphere:** Water and camera-responsive waves, drop splashes, fish-entry animations, plants, crab, sand, bubbles, decorative treasure and animated heater.
- **Fishing helper:** Casting timer with bobber and progress ring; optional lure reminder and a player-activated bait macro.
- **Fish insights:** Resident roster with hover details, Cooking-recipe badges, and optional auction-price estimates when a compatible addon supplies pricing.
- **Performance:** Adjustable 10–30 FPS aquarium animation cap, low-impact mode, spatially filtered schooling and paused visual simulation when the aquarium is hidden. There is no fixed fish-count limit; large collections can still reduce FPS.

## Controls

| Command | Action |
| --- | --- |
| `/vfish` | Open addon options |
| `/vfish on` / `/vfish off` | Enable / disable fishing mode |
| `/vfish toggle` | Toggle fishing mode |
| `/vfish timer` | Test the casting timer |
| `/vfish preview` | Test catch reveal animation |
| `/vfish feed` | Feed live fish |
| `/vfish baitmacro` | Create a player-triggered lure macro (outside combat) |
| `/vfish refresh` | Refresh aquarium information |

See the options window for UI controls, reset, and collection display settings.

## Compatibility and limitations

- Built for WoW Forever using `.toc` interface `16001`. Other WoW clients are not verified.
- Fish hunger/temperature are **simulated in the addon**, not real survival systems. Death never removes a player item.
- The client may restrict macros and item interactions. The addon does not autonomously cast, reel, equip, or delete items.
- Timer detection and optional auction/Cooking integration rely on the client and installed addon APIs.
- Live in-game regression testing is still needed before labeling the release fully verified. See [`Docs/TESTING.md`](Docs/TESTING.md).

## Project structure

```text
VibeFishin.toc        # WoW addon metadata and load order
Core/VibeFishin.lua   # Aquarium runtime and UI
Media/                # Bundled custom artwork
Docs/                 # Architecture and testing
scripts/              # Release packager
.github/workflows/     # Syntax, asset, and ZIP checks
```

The repository's root contains addon source. GitHub release archives wrap these files in the required `VibeFishin/` folder.

## Credits and provenance

- **Creator and maintainer:** Pepkilz.
- **Development and custom art assistance:** OpenAI ChatGPT and image-generation tools were used during the project. Source and assets were iterated on by the project creator.
- **Game-provided art/API:** WoW `Interface\Icons`, `Interface\Buttons`, `Interface\COMMON` and other client paths are assets supplied by Blizzard Entertainment. They are **referenced**, not copied into the repository.
- **Bundled artwork:** `AquariumHeater.tga`, `AquariumHeaterGlow.tga`, `HeaterAura.tga`, `TreasureBody.tga`, `TreasureLid.tga`, `BubbleRing.tga`, `CookingBadge.tga`, and `MinimapRing.tga` were produced in the project's art-development process. No identifiable third-party artist for these bundled files was found in the retained project history. If externally sourced material is identified, proper attribution and permission must be established before release.
- **Heater visual reference:** A reference photograph previously provided by the creator was used for inspiration. The photograph is **not** redistributed; its author and license were not established.
- **Optional third-party ecosystems:** Auctionator and Auction House Database (AHDB) remain independently maintained addons. Their source and artwork are not included here.

**Licensing:** No open-source license has been granted in this repository yet. This is intentional pending Pepkilz's choice of a suitable license and confirmation of asset rights. Do not assume Blizzard assets or unverified third-party works are covered by any project license.

## Contributing and release process

See [`CONTRIBUTING.md`](CONTRIBUTING.md), [`CHANGELOG.md`](CHANGELOG.md), and [`Docs/RELEASE.md`](Docs/RELEASE.md). A GitHub Actions workflow builds and attaches the installable ZIP to a `v*` release tag.

### Feeding timing (v2.0.1)

Pellets remain available for two minutes, even with Low-impact mode enabled. Refreshing inventory does not remove pellets. Once a fish begins nibbling, it takes five seconds to complete a meal and gets a five-minute feeding cooldown.
