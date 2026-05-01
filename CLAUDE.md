# CLAUDE.md — Founder Stack Framework Repo

This is the framework's own working file. When editing in this repo, behave according to the rules below.

## What this repo is

A published workflow framework for non-technical founders. Every file in `workflow/`, `skills/`, and `templates/` ends up symlinked into someone else's project. Treat each command, agent, and hook as a public interface.

## Editing rules

1. **Generic only.** No project-specific terminology, file paths, or domain references. Use `{{paths.*}}` placeholders that resolve from `workflow/project.example.json`.
2. **Test in a clean repo.** Before merging changes to commands/agents/hooks, install into a throwaway target and run them.
3. **Document the contract.** Each command has a header explaining inputs, outputs, and gate behavior.
4. **Backwards compatible.** Don't rename commands or change argument shapes without a deprecation window — installs are symlinks; breaking changes break user projects.

## Open work

- [ ] Genericize `workflow/Engineering-Playbook.md` — currently a verbatim copy from the source project; needs Alignmink references stripped and replaced with `{{paths.*}}` placeholders.
- [ ] Audit `workflow/commands/*.md` and `workflow/agents/*.md` for hardcoded paths.
- [ ] Write the `examples/` reference project so users can see a working install.
- [ ] Decide: ship `npx founder-stack init` wrapper or keep bash-only.

## Source repo

Extracted from the Alignmink Executive CoPilot project on 2026-05-01. The original `.claude/` tree there remains the canonical source until divergence is recorded here.
