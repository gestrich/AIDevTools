## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-enforce` | Run after code changes to verify standards and architecture |

## Background

Plans d through g each investigated a workaround from the binary release pipeline effort and ended with their own release + AIDevToolsDemo verification. This plan is the final consolidation step: run `ai-dev-tools-enforce` across all files touched by those four plans, fix any enforcement issues, then cut a clean final release that represents the fully settled state of all investigations.

**Prerequisites**: Plans d, e, f, and g must all be complete before running this plan.

---

## - [ ] Phase 1: Run `ai-dev-tools-enforce` on all modified files

**Skills to read**: `ai-dev-tools-enforce`

Collect the full list of files changed across Plans d–g by reviewing the commits since the last release before Plan d began. Then run `ai-dev-tools-enforce` on those files:

```sh
git log --name-only --pretty=format: <last-pre-plan-d-tag>..HEAD | sort -u | grep -v '^$'
```

Focus enforcement on Swift source files. YAML workflow files are not in scope for `ai-dev-tools-enforce`.

---

## - [ ] Phase 2: Fix any enforcement issues

**Skills to read**: `ai-dev-tools-enforce`

For each violation found in Phase 1, apply the appropriate fix (layer placement, naming, organization, etc.). Keep fixes minimal — do not refactor beyond what enforcement requires.

After all fixes are committed, push to `main` and confirm CI passes on both platforms:

```sh
git push
gh run watch --repo gestrich/AIDevTools
```

---

## - [ ] Phase 3: Final release and full AIDevToolsDemo validation

**Skills to read**: none

Cut the final release and confirm the complete pipeline is healthy.

1. Confirm the working tree is clean:
   ```sh
   git status --porcelain
   ```

2. Check the latest release tag and run the release script with the next version:
   ```sh
   gh release list --repo gestrich/AIDevTools --limit 5
   ./scripts/release.sh vX.Y.Z
   ```

3. Watch the full Release workflow and confirm all five jobs pass:
   ```sh
   gh run watch --repo gestrich/AIDevTools
   ```
   - `Test (macos-latest)`
   - `Test (ubuntu-latest)`
   - `Build macOS`
   - `Build Linux`
   - `Create Release`

4. Trigger the end-to-end binary test in AIDevToolsDemo:
   ```sh
   gh workflow run test-binary.yml --repo gestrich/AIDevToolsDemo -f version=vX.Y.Z
   gh run watch --repo gestrich/AIDevToolsDemo
   ```

5. Confirm all steps pass: Resolve version, Download release assets, Verify checksum, Verify attestation, Install binary, `ai-dev-tools-kit --help` exits 0, `ai-dev-tools-kit prradar --help` exits 0.
