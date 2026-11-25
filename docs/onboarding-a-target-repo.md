# Onboarding a target repo

Repeat these steps for each repo the factory should work on. Complete [setup.md](setup.md) first.

Onboard public repos only. This repo is public, so its work items, run logs and target config are visible to anyone.

Placeholders: `TARGET=kelvvinn/<target-repo>` and `F=kelvvinn/copilot-engineering-factory`.

## Checklist

| # | Step | Who |
|---|---|---|
| 1 | Target has branch protection with human approval and required CI | Target repo admin |
| 2 | Factory App installed on the target and its private dependency repos | Org owner / App manager |
| 3 | Private dependencies can be fetched over HTTPS | Factory maintainer |
| 4 | Target registered in factory config | Factory maintainer (PR) |
| 5 | `factory` label exists in the target | Target repo admin |
| 6 | Smoke test passes | Factory maintainer |

## 1. Check target protection [Target repo admin]

The factory must never be able to merge on its own. On the default branch, the target needs:

- **Require a pull request** with at least **1 approval**, stale approvals dismissed.
- **Required status check** for the target's CI.
- No bypass entry for the `copilot-engineering-factory` App.

```bash
gh api repos/$TARGET/rulesets --jq '.[].id' | xargs -I{} gh api repos/$TARGET/rulesets/{} \
  --jq '{name, bypass: [.bypass_actors[].actor_id], rules: [.rules[] | {type, approvals: .parameters.required_approving_review_count, checks: .parameters.required_status_checks}]}'
```

Recommended: turn on `require_code_owner_review` so CODEOWNERS approve agent PRs.

## 2. Install the App on the target [Org owner / App manager]

Org → Settings → GitHub Apps → `copilot-engineering-factory` → **Configure** → *Repository access* → **Only select repositories** → add:

- the target repo
- any **private dependency repos** the target installs from (the App only needs Contents read on those)

Check with a token minted from the App, for example in a factory workflow run:

```bash
gh api /installation/repositories --jq '.repositories[].full_name'
```

## 3. Private dependencies [Factory maintainer]

List the target's private dependency repos in its `private_deps` (step 4). The build stage then mints a read-only App token for those repos and rewrites `ssh://git@github.com/` to HTTPS for the setup command only. No deploy keys are needed.

## 4. Register the target [Factory maintainer, via PR]

Add an entry to [.github/factory/config.yml](../.github/factory/config.yml) using a `feat:` PR:

```yaml
targets:
  - repo: kelvvinn/<target-repo>
    default_branch: main
    runtime:
      python: "3.12"
      java: "21"             # omit if not needed
    setup:   <setup-command>   # e.g. pip install -r requirements.txt
    lint:    <lint-command>
    test:    <test-command>    # e.g. python -m pytest
    private_deps: [kelvvinn/<private-dep-repo>]
```

Omit `default_branch` or `runtime.python` to use the file's `defaults`. The Conductor reads this file at run time, so no recompile is needed. The build stage's firewall allows the `defaults` and `python` ecosystems. A target that needs more must add them to `network:` in [build.md](../.github/workflows/build.md) and recompile.

## 5. Create the PR label [Target repo admin]

```bash
gh label create factory --repo $TARGET --color 5319E7 --description "PR raised by copilot-engineering-factory"
```

## 6. Smoke test [Factory maintainer]

1. Create a work item in `$F` from the **Work item** form, with the target set and a trivial change (e.g. fix a README typo). Label it `factory:ready`.
2. Expect: a PR in the target labelled `factory`, target CI starts, and the work item reaches `factory:ready-for-human`.
3. Close the PR without merging.

> PRs created with an App token **do** trigger the target's GitHub Actions. Other CI services (e.g. CircleCI) trigger through their own GitHub integration.

## Offboarding

1. Remove the target from `.github/factory/config.yml` (PR).
2. Remove the repo from the App installation (step 2).

---

## Appendix: `<target-repo>`

Copy this table for each onboarded target and replace the placeholders.

| Item | Value |
|---|---|
| Protection | Ruleset `<ruleset-name>`: `<n>` approvals, stale approvals dismissed, required check `<ci-check>` |
| CI | `<ci-system>` `<ci-definition-path>` (`<ci-steps>`) |
| Runtime | `<runtime-versions>` |
| Setup | `<setup-command>` |
| Private deps | `kelvvinn/<private-dep-repo>` over `git+ssh`. Install the App on `<private-dep-repo>` (step 2) |
| Commit / PR title | `<commit-convention>`. Factory PR titles must match |
| Agent context | The target's `.github/copilot-instructions.md`, `.github/instructions/` and `.github/agents/` are in the checkout. Check in the V1 trial run that they're picked up. If not, the stage includes them in the prompt |
| Agent context | The target's `.github/copilot-instructions.md`, `.github/instructions/` and `.github/agents/` are in the checkout. Check in the V1 trial run that they're picked up. If not, the stage includes them in the prompt |
