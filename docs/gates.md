# Gates — What Each One Actually Checks

Gates are the framework's enforcement mechanism. They are slash commands that delegate to specialized subagents, with shell-level evidence (test runs, lint output, DB queries) backing the verdict.

## `/test-gate <feature>`

**When to run:** before implementation starts.

**What it does:** the `test-author` subagent reads the spec and writes failing tests that establish the feature contract. Tests go red. Implementation later turns them green.

**Pass criteria:**
- Tests exist and are runnable
- Tests fail (proving they're testing something that doesn't yet work)
- Tests cover the contract from the spec, not implementation details

**Why it matters:** non-technical founders can't review test quality after the fact. Writing tests first turns "did we test this?" into a binary.

## `/design-gate <scope>`

**When to run:** after a UI feature compiles.

**What it does:** the `design-auditor` subagent compares implemented code against the design spec, project tokens, and (if connected) Figma screenshots. Returns a structured pass/fail with a gap list.

**Pass criteria:**
- Component uses design tokens, not raw values
- Visual structure matches spec/Figma
- Accessibility rules from the component spec are enforced

**Why it matters:** UI drift is invisible to non-designers. The gate catches it before it ships.

## `/schema-gate <migration>`

**When to run:** when a DB migration is being authored or edited.

**What it does:** the `schema-analyst` subagent reviews the migration for forward-compat, RLS coverage, data-loss risk, and index impact. Queries the live DB read-only to confirm assumptions.

**Pass criteria:**
- Migration is additive (or has a documented destructive plan)
- RLS policies cover new tables/columns where multi-tenant
- No surprise locks on large tables
- Reversible, or rollback documented

**Why it matters:** data loss is the worst kind of bug. The gate makes it harder to ship one accidentally.

## `/deploy-gate <env>`

**When to run:** after a deploy completes.

**What it does:** the `deploy-verifier` subagent runs health checks, smoke tests via Playwright, and scans logs for the deployed environment. Does NOT deploy. Does NOT roll back.

**Pass criteria:**
- Health endpoint returns 200
- Critical user flow works end-to-end in a real browser
- No new error patterns in logs since last green deploy

**Why it matters:** "the build passed CI" is not the same as "the feature works in production."

## `/publish-gate`

**When to run:** before publishing an npm package.

**What it does:** packs the tarball, installs into a tmpdir, runs the configured smoke command, asserts expected output. Catches the "worked locally but the published tarball is broken" class of bug.

## How gates compose

A typical phase: `/spec-intake` → plan approval → `/test-gate` (red) → implement (green) → `/design-gate` → `/schema-gate` (if applicable) → deploy → `/deploy-gate staging` → `/handoff <phase>`.

Skipping a gate is allowed. It's also tracked. The handoff doc lists which gates passed and which were skipped — so future-you can see what corners got cut.
