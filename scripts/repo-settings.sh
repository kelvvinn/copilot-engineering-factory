#!/usr/bin/env bash
set -euo pipefail

# Defaults to the repo of the clone this runs in.
R="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

echo "Merge settings: squash only, PR title as commit, delete merged branches, PRs from collaborators only"
gh api -X PATCH "repos/$R" \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true -F allow_update_branch=false \
  -F has_issues=true -F has_wiki=false -F has_projects=false \
  -f pull_request_creation_policy=collaborators_only > /dev/null

echo "Workflow token: read-only, cannot approve PRs"
gh api -X PUT "repos/$R/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false

echo "Stop switch: FACTORY_ENABLED=false (only if not already set)"
gh variable list --repo "$R" --json name --jq '.[].name' | grep -qx FACTORY_ENABLED \
  || gh variable set FACTORY_ENABLED --repo "$R" --body false

echo "Security: secret scanning, push protection, Dependabot alerts"
gh api -X PATCH "repos/$R" --input - > /dev/null <<'JSON' || echo "  (skipped: secret scanning not available on this plan)"
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
JSON
gh api -X PUT "repos/$R/vulnerability-alerts"

echo "Ruleset 'main-protection' on the default branch"
# Every change goes through a squash-merged PR with passing checks and code owner (CODEOWNERS) approval.
# Repo admins may merge PRs without approval (GitHub never allows self-approval, including on Copilot PRs
# you asked for), but never push directly. The factory App may push, so `bump` can commit the release.
app_id="${FACTORY_APP_ID:-$(gh api /apps/copilot-engineering-factory --jq .id 2>/dev/null || true)}"
if [ -z "$app_id" ]; then
  echo "  (skipped: factory App not found. Create it (docs/setup.md step 2) or set FACTORY_APP_ID, then re-run)"
else
  ruleset=$(cat <<JSON
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "bypass_actors": [
    {"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request"},
    {"actor_id": $app_id, "actor_type": "Integration", "bypass_mode": "always"}],
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 1,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": true,
      "require_last_push_approval": false,
      "required_review_thread_resolution": true,
      "allowed_merge_methods": ["squash"]}},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": false,
      "required_status_checks": [
        {"context": "commitizen", "integration_id": 15368},
        {"context": "lint", "integration_id": 15368}]}}
  ]
}
JSON
)
  id=$(gh api "repos/$R/rulesets" --jq '.[] | select(.name=="main-protection") | .id')
  if [ -n "$id" ]; then
    gh api -X PUT "repos/$R/rulesets/$id" --input - <<< "$ruleset" > /dev/null
  else
    gh api -X POST "repos/$R/rulesets" --input - <<< "$ruleset" > /dev/null
  fi
fi

echo "Factory state labels"
while IFS='|' read -r name colour desc; do
  gh label create "$name" --repo "$R" --color "$colour" --description "$desc" --force
done <<'LABELS'
factory:ready|0E8A16|Work item queued for the factory
factory:planning|C5DEF5|Plan stage running
factory:building|1D76DB|Build stage running
factory:in-review|FBCA04|Review stage running
factory:changes-requested|D93F0B|Reviewer returned FAIL; fix stage queued
factory:ready-for-human|5319E7|All agent reviews passed; awaiting human review
factory:needs-human|B60205|Max rounds reached or stage failed; human action needed
work-item|BFDADC|Work item for the factory
LABELS

echo "Done."
