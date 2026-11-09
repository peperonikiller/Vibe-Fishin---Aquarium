# Release process

1. Test the new addon in the WoW Forever client, especially fishing, roster and encyclopedia, feeding, persistence and performance.
2. Update the version in `VibeFishin.toc`, `VibeFishin_Forever.toc`, `Core/VibeFishin.lua` header, README and CHANGELOG.
3. Run `lua5.1 scripts/check_syntax.lua Core/VibeFishin.lua` and `python3 scripts/package_release.py --check`.
4. Push to `main`. The release workflow validates and packages an asset named `VibeFishin-vVERSION-forever.zip`, with a single `VibeFishin/` folder at the archive root.
5. Confirm the GitHub release is marked **Latest** (not pre-release), and download its asset for a final ZIP check.

## WowUpHub

The Hub supports the `VibeFishin_Forever.toc` flavor manifest for WoW Forever and reads the installable release asset. The image at `.previews/vibe-aquarium.png` is available for screenshot previews. Upload that PNG to repository **Settings → Social preview** to set the Hub's icon. Then contact a WowUp Discord moderator or Zakrn with the repository link to request WowUpHub indexing. A valid release is required but does not automatically create a listing.

See https://wowup.io/guide/wowup/hub.

## Other managers

Wago and CurseForge require separate project setup and approval. A GitHub release does not create a listing there.
