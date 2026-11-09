# Contributing

Thank you for helping improve Vibe - Fishing Aquarium.

1. Open an issue explaining your bug, performance data, or feature proposal.
2. Keep WoW Forever interface `16001` compatibility in mind; avoid automatically protected player actions.
3. Make focused changes in `Core/VibeFishin.lua` and maintain the existing load order and saved settings (`VibeFishinDB`).
4. Run `texlua scripts/check_syntax.lua Core/VibeFishin.lua` and `python scripts/package_release.py --check`.
5. Test loading, fishing catches, roster, feeding, dead-fish survival, performance and texture rendering in the client. Document which tests you actually ran.
6. For new code or assets from others, include source URLs, creator, license, modifications and redistribution rights in the README. Do not add copyrighted third-party assets without permission.

No open-source license has been chosen yet; please contact Pepkilz before substantial third-party code contributions so rights can be clarified.
