# Tallow Manager

Companion installer and project manager for Tallow Engine. Work continues on `rename/tallow`; main is unchanged.

Check out the engine's `rename/tallow` branch as `../Tallow`, build its native dependencies, and run `BeefBuild -config=Debug` here. Alternatively, create a project workspace with the Tallow launcher or package with `Tallow/tools/build_player.py --project .`.

The manager uses `project.tallow`, Tallow component namespaces, `tallow-version.json`, and `Tallow-Windows.zip` / `Tallow-Linux.zip`. Repository URLs retain their current GitHub names until the coordinated repository cutover. New engine packages must be published before this branch can install them.

Validation: Linux Debug build, standalone player packaging, and `python3 tools/test_engine_install.py` pass. The installer fixture downloads over loopback HTTP, verifies checksums, installs the official ZIP folder layout, rejects duplicate immutable builds and bad checksums, and verifies staging cleanup. Windows installation still needs validation.
