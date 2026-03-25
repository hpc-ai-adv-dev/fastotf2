# Comparisons

FastOTF2 keeps multiple implementation styles in one repository, but they do not all serve the same purpose.

## Primary Supported Workflow

The main supported workflow is the Chapel-based trace-to-table path centered on [../apps/FastOTF2Converter](../apps/FastOTF2Converter).
That is the implementation the repository optimizes for in its structure, onboarding, and future packaging.

## Chapel

The Chapel code serves two roles:

- the reusable OTF2 package located in [../src](../src)
- the application and Mason examples located in [../apps](../apps) and [../example](../example)

Chapel is the main implementation language for FastOTF2.

## Python

The Python scripts and notebooks are useful for:

- quick experimentation
- API exploration
- showing what a high-level interface looks like
- comparing ergonomics and performance expectations

They should be treated as comparison and tutorial material, not as the primary product surface.

## C

The C implementations are useful for:

- understanding the low-level OTF2 API
- illustrating the callback-heavy baseline implementation style
- comparing what the Chapel layer improves

They should remain available as reference implementations, not as the main user entry point.

## Documentation Intent

Users who want to get work done should start with [quickstart.md](quickstart.md).
Users who want to understand tradeoffs and implementation strategy should continue with [../DEMO.md](../DEMO.md) and the comparison materials.