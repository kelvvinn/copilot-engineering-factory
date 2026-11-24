# Factory setup (one-off)

Do these steps once. To give the factory access to a repo afterwards, follow [onboarding-a-target-repo.md](onboarding-a-target-repo.md).

**Who:** **[Org owner]** steps need the owner of the `kelvvinn` account or a GitHub App manager. **[Repo admin]** steps need an admin of this repo.

## 1. Org prerequisites [Org owner]

| Setting | Where | Value |
|---|---|---|
| Copilot plan | Org → Settings → Copilot | Business or Enterprise, **centrally billed** (required for `copilot-requests: write`. Org-owned repos only. For personal plans, see the note below) |
| Copilot access for Actions tokens | Org → Settings → Copilot → Policies | Allow Copilot usage billed to the organisation (org plans only). If the first run fails with a Copilot auth error, check this policy first |
| Allowed Actions | Org → Settings → Actions → General | Allow `actions/*` and `github/*` (covers gh-aw compiled workflows). If you use an allow-list, add `github/gh-aw/*` |
| Workflow token | This repo → Settings → Actions → General | Read-only by default. Actions cannot approve PRs (applied by `scripts/repo-settings.sh`) |

> Model calls use the built-in Actions token (`permissions: copilot-requests: write`). **No PAT, no service account and no Copilot seat are needed for the factory.** (Org plans only. On a personal plan such as Copilot Pro or Pro+, omit the permission and set the `COPILOT_GITHUB_TOKEN` secret to a fine-grained PAT with the **Copilot Requests** permission. See [gh-aw authentication](https://github.github.com/gh-aw/reference/auth/#copilot_github_token).)

## 2. Create the factory GitHub App [Org owner]

Org → Settings → Developer settings → GitHub Apps → **New GitHub App**

| Field | Value |
|---|---|
| Name | `copilot-engineering-factory` |
| Homepage URL | `https://github.com/kelvvinn/copilot-engineering-factory` |
| Webhook | **Uncheck** Active |
| Where can it be installed | Only on this account |

**Repository permissions** (everything else `No access`):

| Permission | Access | Used for |
|---|---|---|
| Contents | Read and write | Check out the target, push PR branches |
| Pull requests | Read and write | Open PRs, push fixes, post review comments |
| Issues | Read and write | Comment on and label target issues (optional) |
| Commit statuses | Read-only | Read target CI results (e.g. ADO `ci`) |
| Checks | Read-only | Read target CI results (Actions) |
| Metadata | Read-only | Mandatory |

Do **not** grant `Workflows` or `Administration`. This stops agents changing target CI or bypassing protection.

Then:
1. **Generate a private key** (`.pem`) and note the **Client ID**.
2. **Install App** → `kelvvinn` → **Only select repositories** → `copilot-engineering-factory`. Add targets later as described in the onboarding guide.

## 3. Store the App credentials [Repo admin]

```bash
R=kelvvinn/copilot-engineering-factory
gh variable set FACTORY_APP_CLIENT_ID --repo $R --body "<client-id>"
gh secret set FACTORY_APP_PRIVATE_KEY --repo $R < copilot-engineering-factory.private-key.pem
shred -u copilot-engineering-factory.private-key.pem  # don't keep the key locally
```

The stages mint short-lived App tokens from these through their `github-app:` frontmatter (see [build.md](../.github/workflows/build.md)).

## 4. Repo configuration [Repo admin]

Run once. The script is safe to re-run and is the source of truth for these settings:

```bash
bash scripts/repo-settings.sh
```

| Setting | Value |
|---|---|
| Visibility | Private |
| Merge | Squash only, commit message = PR title, delete branch on merge |
| Ruleset `main-protection` | Disabled (rulesets on private repos need GitHub Pro, and the owner is the only collaborator). To enable, uncomment it in the script |
| Labels | `factory:ready`, `factory:planning`, `factory:building`, `factory:in-review`, `factory:changes-requested`, `factory:ready-for-human`, `factory:needs-human`, `work-item` |
| Variable `FACTORY_ENABLED` | `false`. The Conductor does nothing until this is `true` (stop switch) |
| Workflow token | Read-only. Cannot approve PRs |
| Security | Secret scanning, push protection, Dependabot alerts |

Check:

```bash
R=kelvvinn/copilot-engineering-factory
gh api repos/$R --jq '{private,allow_squash_merge,allow_merge_commit,allow_rebase_merge,delete_branch_on_merge}'
gh variable list --repo $R
gh label list --repo $R --search factory
```

## 5. Developer tooling

```bash
gh extension install github/gh-aw      # pin later with: gh extension install github/gh-aw --pin <tag>
gh aw version
```

Set up the Python tooling (Commitizen and pre-commit from `requirements.txt`) as described in [Contributing](../README.md#contributing).

After editing any `.github/workflows/*.md`, run `gh aw compile` and commit the `.lock.yml` files.

## 6. Go live

1. Onboard at least one target repo ([onboarding guide](onboarding-a-target-repo.md)).
2. `gh variable set FACTORY_ENABLED --repo kelvvinn/copilot-engineering-factory --body true`
3. To stop everything immediately, set it back to `false`.
