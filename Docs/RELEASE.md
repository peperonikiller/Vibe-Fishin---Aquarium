# Release instructions

1. Confirm the linked GitHub repository, its owner and the intended default branch.
2. Confirm permissions for all included assets and select an appropriate source/artwork license (or retain no license if preferred).
3. Run `lua5.1 scripts/check_syntax.lua Core/VibeFishin.lua` and `python scripts/package_release.py --check`.
4. Verify the addon in a real WoW Forever client using `Docs/TESTING.md`.
5. Commit the source files to the repository (not the generated ZIP, which belongs in Releases).
6. Create and push a `v2.0.0` tag only once the in-game test checklist passes. The GitHub Actions workflow automatically creates a GitHub Release with the installable `VibeFishin-v2.0.0-forever.zip`.

## Packaging

At repository root:

```sh
python scripts/package_release.py
```

The archive contains the top-level `VibeFishin/` folder with `VibeFishin.toc`, `Core/`, `Media/`, `Docs/`, and README. It does not package GitHub development infrastructure.

## Known limitations

- Client-specific Lua globals, textures and protected actions cannot be exhaustively tested by a standalone parser.
- This release has not been tested in the live WoW Forever client during artifact preparation.

## WowUp / CurseForge distribution

WowUp: create a GitHub release for tag `v2.0.0` with asset `VibeFishin-v2.0.0-forever.zip`. The archive must contain `VibeFishin/VibeFishin.toc` as the top-level addon folder. Install from repository URL for managed updates, not a one-time ZIP URL.

CurseForge: upload that same ZIP as a file to a CurseForge project for managed installs/updates. GitHub release publication alone does **not** publish to CurseForge. The app may not recognize a non-official WoW client as a managed game profile.
