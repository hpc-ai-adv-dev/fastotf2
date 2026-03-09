# Chapel Package Source

This directory is the target Mason-friendly home for the FastOTF2 Chapel package source.

The Mason package has now been introduced at the repository root via `Mason.toml`.

Current state during migration:

- `src/` contains a mirrored copy of the reusable Chapel OTF2 modules.
- `src/FastOTF2.chpl` is the package entry module for Mason.
- `src/OTF2.chpl` remains the umbrella public module used by the current codebase.
- `chpl/_chpl/` remains in place temporarily so existing Make-based workflows continue to work.

This means the repository now has a package-oriented source layout without breaking the existing Chapel build paths yet.

## Make And Mason During Migration

The repository currently supports both build styles:

- Make-based builds under `chpl/` remain the existing workflow for the applications.
- Mason now provides the package-oriented workflow for the reusable Chapel library in `src/`.

The default OTF2 dependency paths are intentionally aligned across both systems:

- include path: `/opt/otf2/include`
- library path: `/opt/otf2/lib`
- linked library: `-lotf2`

If your OTF2 installation lives elsewhere, Make users can continue overriding `OTF2_INCLUDE` and `OTF2_LIB`.
Mason users can override the defaults by supplying additional compiler options when invoking Mason.