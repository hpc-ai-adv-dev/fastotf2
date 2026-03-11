# Chapel Package Source

This directory is the canonical Mason-friendly home for the FastOTF2 Chapel package source.

The repository root is the FastOTF2 Mason library package via `Mason.toml`.

Current structure:

- `src/` contains the reusable Chapel OTF2 modules for the root FastOTF2 package.
- `src/FastOTF2.chpl` is the package entry module for Mason.
- `src/OTF2.chpl` remains the umbrella public module used by the current codebase.

## Build Model

The supported build style is Mason:

- The root FastOTF2 package uses Mason at the repository root.
- The trace converter application package uses Mason under `apps/trace_to_csv`.

The default OTF2 dependency paths are intentionally aligned across both systems:

- include path: `/opt/otf2/include`
- library path: `/opt/otf2/lib`
- linked library: `-lotf2`

If your OTF2 installation lives elsewhere, override the defaults by supplying additional compiler options when invoking Mason.