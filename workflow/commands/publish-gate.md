---
description: Pre-publish smoke verification — pack, install into a tmpdir, run the configured smoke command, assert expected output. Catches the "code worked locally but the published tarball is broken" class of bug.
argument-hint: [artifact name | empty for all]
---

You are running the publish gate. This gate runs **BEFORE** the user runs `npm publish` (or equivalent). It validates that the artifact you're about to ship will actually work when a fresh consumer installs it.

**Arguments:** `$ARGUMENTS`

## Why this gate exists

`prepublishOnly` runs unit tests against your local source tree. Unit tests do not catch:

- Files referenced from `package.json` (bin, hooks, scripts) that are missing from the `files` allowlist → consumer install crashes with `MODULE_NOT_FOUND`.
- Postinstall hooks that work in dev because the file lives in the working directory, but fail in install because the working directory is the npm cache.
- Build artifacts in `dist/` that are stale because someone forgot to run `npm run build` before publishing.
- Any "works on my machine" gap between the dev checkout and the tarball.

This gate closes that gap by installing the actual tarball and running it as a fresh consumer.

## Steps

1. Read `.claude/project.json`. Extract the `release_artifacts` array. If absent or empty, fail fast: *"publish-gate requires `release_artifacts` in project.json. Skip this gate if the project doesn't ship a packaged artifact."*

2. **Filter to scope.** If `$ARGUMENTS` is empty, run all artifacts. Otherwise, run only the artifact whose `name` matches `$ARGUMENTS`. If no match, list available names and fail.

3. **For each artifact**, in sequence:

   a. **`cd` into `path`** (the artifact's source root, e.g. `apps/<package-name>`).

   b. **Pack.** Run `npm pack --pack-destination /tmp/<artifact-name>-pack` (or the equivalent for the artifact `type`: `npm` → `npm pack`, `docker` → `docker build`, `python` → `python -m build`). Capture the output file path.

   c. **Install into a fresh tmpdir.** `mktemp -d` → `cd` into it → install the local tarball (`npm install <tarball-path>` or equivalent). For `npm`, use `--prefix .` to keep the install local to the tmpdir, so this gate never touches the user's global modules.

   d. **Run the smoke command.** Execute `smoke` (the field on the artifact entry — e.g. `<package-name> --version` or `<package-name> doctor`) from inside the tmpdir, with the local `node_modules/.bin` on PATH if needed.

   e. **Assert expected output.** Check the smoke command's stdout for the `expect_in_output` substring. Capture exit code; non-zero is a hard fail.

   f. **Clean up.** Remove the tmpdir.

4. **Report.** For each artifact: PASS / FAIL, the smoke command run, the matched substring (or what was missing), and the path to the tested tarball.

5. **On all-PASS:** record a session marker — `touch .claude/.publish-gate-passed-<artifact-name>`. The next `/handoff` checks for these.

6. **On any FAIL:** print the smoke command's full output, the missing-substring detail, and STOP. Do not auto-retry. Do not auto-fix. The user's next step is to diagnose (likely a missing entry in the `files` allowlist or a stale `dist/` build).

## Notes

- This gate **does not publish** — it only validates. The user runs `npm publish` themselves after the gate passes.
- The gate is **fast** when nothing's wrong: pack + install + one CLI invocation, typically under 10 seconds for a small npm package.
- For `type: "docker"`, the smoke happens inside a `docker run --rm <built-image> <smoke>` invocation. For `type: "python"`, `pip install <wheel>` into a venv, then `python -m <smoke>`.
- This is a sibling of `/deploy-gate`, not a replacement. A project that publishes a CLI **and** deploys a hosted service runs both. A pure npm package runs only `/publish-gate`.
- The `expect_in_output` field is a literal substring check — keep it specific enough to detect the right state and short enough to be stable across versions. Good: `"up to date"`. Bad: full version string.
