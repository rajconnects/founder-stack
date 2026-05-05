---
description: Produce low-fidelity UX artifacts — extends components_spec and flow_spec, optionally creates rough Figma frames labelled [WIREFRAME]. Sets `.ux-wireframe-passed-<scope>` marker on success. Layer 1.7 of the workflow; precedes /ux-mockup.
argument-hint: <spec path | scope name | auto> [--source <figma-url|node-id>] [--skip-when-trivial]
---

You are running the wireframe step of the UX design layer.

**Arguments:** `$ARGUMENTS`

## Steps

1. **Resolve scope.** Parse `$ARGUMENTS`. If empty or `auto`, read `spec_roots.frontend` then `spec_roots.build_plans` from `.claude/project.json` and pick the most recently modified spec file under those roots. Otherwise use the path/scope given. If no spec resolves, fail loudly: `ux-wireframe requires a spec path or scope. Try /ux-wireframe auto if a recent frontend spec exists.`

2. **Compute the scope slug.** Slugify the scope label (or the spec's primary component name) for marker filenames: lowercase, alphanumerics + dashes only.

3. **Resolve config and inline.** Read `.claude/project.json` once. Extract: `spec_roots`, `design_system.components_spec`, `design_system.flow_spec`, `design_system.tokens`, `design_system.principles` (may be null), `design_system.figma.file_key`, `design_system.figma.screens`, `stack.frontend`, `stack.frontend_root`. If `stack.frontend` is null, fail: `ux-wireframe only runs for frontend specs (stack.frontend is null).` If `components_spec` or `flow_spec` is null, fail: `ux-wireframe requires components_spec and flow_spec paths.`

4. **Launch `ux-wireframer`** with a self-contained prompt containing: the resolved spec path, scope label and slug, the inlined config fields above, the `--source` reference (if any), and the `--skip-when-trivial` flag (if any). Do NOT ask the agent to re-read `project.json`.

5. **Print the agent output verbatim.** Do not soften or reinterpret. The agent's output is the wireframe deliverable.

6. **Mark on success.** If verdict is `ARTIFACTS_PRODUCED`, `touch .claude/.ux-wireframe-passed-<scope-slug>`. On `ERROR`, do not write the marker.

7. **Closing line.** On success print: `wireframe ready: review the [WIREFRAME] frames in Figma, then run /ux-mockup <scope>`.

## Notes

- `--skip-when-trivial` is for one-line scopes that don't warrant Figma frames. The agent still extends `components_spec` / `flow_spec` and writes the marker.
- The marker is gitignored and per-session. `.claude/.ux-wireframe-passed-<scope-slug>` is consumed by `/ux-mockup` as a hard prerequisite.
- If `design_system.figma.file_key` is null, the agent skips Figma writes entirely and still produces the spec extensions.
