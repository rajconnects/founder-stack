# Design Principles

Project-owned design opinions that `ux-wireframer` applies on top of the framework's correctness floor (a11y semantics, tokens-not-values, explicit states, copy-as-props).

Copy this file to your project (e.g. `docs/design-principles.md`), edit the sections to reflect your stance, and point `design_system.principles` in `project.json` at the path. The agent reads it once per scope, greps for relevant sections, and cites which principles applied.

If a section doesn't apply to your project, delete it. Empty sections are noise.

## Touch & input

- Minimum touch target: 44×44 px (Apple HIG) or 48×48 dp (Material). Pick the one your platform follows and stick with it.
- Pointer + touch parity: every interaction works with both. No hover-only affordances.

## Density

- Default density level: comfortable | compact | dense.
- Allow density override per surface? Yes / no.

## Motion & animation

- Default transition duration: 150ms ease-out for state changes; 250ms for entrances.
- Reduced-motion support: every transition wraps `@media (prefers-reduced-motion)`.
- Disallowed: bouncy springs, parallax, attention-grabbing loops.

## Layout & grid

- Grid columns: 4 (mobile) / 8 (tablet) / 12 (desktop).
- Gutter: `--spacing-md`.
- Page max-width: `--layout-max-content`.

## Variants

- Default size scale: sm / md / lg. No xs/xl unless the spec demands.
- Default intent scale: neutral / primary / danger. No "warning" or "info" unless the spec demands.

## Copy voice

- Tone: <e.g., direct, plainspoken, no marketing puffery>.
- Reading level: 8th grade.
- Forbidden: exclamation points outside celebration moments, "delight", "magic", "powerful".

## Empty states

- Every list/table/grid has a designed empty state — never blank.
- Empty state explains *why* it's empty + the next action the user can take.

## Loading states

- Skeleton screens for layouts with predictable shape; spinners for indeterminate actions.
- Never show a spinner for less than 200ms — flash is worse than nothing.

## Error states

- Error copy names what happened, what to try, and how to escape.
- Inline errors near the field; toast errors for system-level failures only.
