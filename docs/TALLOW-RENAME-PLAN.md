# Tallow Manager rename (branch-only)

Work continues on `rename/tallow`; main is unchanged. No compatibility aliases or old-format readers are required.

The Manager uses Tallow namespaces, serialized components, `project.tallow`, `tallow-version.json`, and Tallow release assets. Its source workspace expects the built engine in `../Tallow`. Catalog and artwork URLs point at this repository's rename branch rather than the game Hub's catalog. Update those URLs during the coordinated repository cutover.

Linux Debug compilation and standalone player packaging pass. `python3 tools/test_engine_install.py` validates official ZIP folder layout, mandatory checksums, duplicate immutable installs, and staging cleanup against a local HTTP server.

Before merging: validate Windows installation and project launch, publish matching engine packages, coordinate repository URLs and release assets, and obtain explicit merge approval.
