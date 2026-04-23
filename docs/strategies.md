# Partition Strategies

The FastOTF2 Converter uses partition strategies to distribute trace reading across tasks and locales.

**Default:** `locgroup_block` (single-locale) or `locgroup_dist_block` (multi-locale).

## Strategy Comparison

| Strategy | CLI Flag | Parallelism | Merge | Use Case |
|----------|----------|-------------|-------|----------|
| **Serial** | `serial` | None | No | Debugging, baseline |
| **Loc Block** | `loc_block` | Per-location | Yes | Medium traces, simple parallelism |
| **Loc Group Block** | `locgroup_block` | Per-group | No | Medium/large traces, single-locale (default) |
| **Loc Group Dist Block** | `locgroup_dist_block` | Per-locale + Per-group | No | Large traces, multi-locale (default) |

## Quick Reference

- **`serial`**: Sequential read, no parallelism. Use for debugging.
- **`loc_block`**: Partitions by location; merge required. Scales with cores.
- **`locgroup_block`**: Partitions by location group; no merge. Recommended for single-locale.
- **`locgroup_dist_block`**: Distributes groups across locales. Recommended for multi-locale.
