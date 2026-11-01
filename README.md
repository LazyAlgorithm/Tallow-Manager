# Tallow Manager

Native installer and project manager for [Tallow Engine](https://github.com/LazyAlgorithm/Tallow).

Check out the engine as `../Tallow`, build its native dependencies, and run `BeefBuild -config=Release` here. Alternatively build a standalone player with `../Tallow/tools/build_player.py . --output dist/TallowManager-Linux`.

The Manager installs exact engine builds side by side, verifies required SHA-256 checksums and immutable engine identities, and rejects duplicate installs. It uses `project.tallow`, `tallow-version.json`, and Tallow-named release ZIPs. Linux build, packaging, rendered launch and native installer checks passed during the release cutover.
