---
description: Build stage. Implements a work item in its target repository and opens a pull request with evidence.
on:
  workflow_call:
    inputs:
      work_item:
        description: Work item issue number in this repository
        required: true
        type: number
      target_repo:
        description: Target repository (owner/repo), registered in .github/factory/config.yml
        required: true
        type: string
      base_branch:
        description: Target branch the PR merges into
        required: true
        type: string
      change_type:
        description: Commitizen type for the PR title
        required: true
        type: string
      python_version:
        required: true
        type: string
      java_version:
        description: JDK version to install. Empty for none
        required: false
        type: string
        default: ""
      setup:
        description: Command that installs the target's dependencies
        required: false
        type: string
        default: ""
      private_deps:
        description: Comma-separated names of private dependency repos (no owner) the setup command fetches
        required: false
        type: string
        default: ""
      lint:
        required: false
        type: string
        default: ""
      test:
        required: false
        type: string
        default: ""

# Personal Copilot plans use the COPILOT_GITHUB_TOKEN secret. Org-billed Copilot: set `copilot-requests: write` (docs/setup.md).
permissions:
  contents: read
  issues: read
  copilot-requests: none

engine:
  id: copilot
  agent: data-engineer
  model: claude-opus-5.5

timeout-minutes: 45
max-ai-credits: 1000

# Short-lived App tokens for target checkout, reading the work item and safe outputs.
github-app:
  client-id: ${{ vars.FACTORY_APP_CLIENT_ID }}
  private-key: ${{ secrets.FACTORY_APP_PRIVATE_KEY }}
  owner: ${{ github.repository_owner }}

checkout:
  - repository: ${{ inputs.target_repo }}
    ref: ${{ inputs.base_branch }}
    path: target
    current: true
    fetch-depth: 0

network:
  allowed: [defaults, python]

tools:
  edit:
  bash: [":*"]
  github:
    toolsets: [issues]

steps:
  - uses: actions/setup-python@v7
    with:
      python-version: ${{ inputs.python_version }}

  - uses: actions/setup-java@v6
    if: inputs.java_version != ''
    with:
      distribution: temurin
      java-version: ${{ inputs.java_version }}

  # Read-only token, so private dependencies installed over git+ssh resolve through HTTPS.
  # It is passed through step-scoped GIT_CONFIG_* variables and revoked before the agent starts.
  - name: Mint dependency token
    id: deps-token
    if: inputs.private_deps != ''
    uses: actions/create-github-app-token@v3
    with:
      client-id: ${{ vars.FACTORY_APP_CLIENT_ID }}
      private-key: ${{ secrets.FACTORY_APP_PRIVATE_KEY }}
      owner: ${{ github.repository_owner }}
      repositories: ${{ inputs.private_deps }}
      permission-contents: read

  - name: Install target dependencies
    if: inputs.setup != ''
    working-directory: target
    env:
      SETUP: ${{ inputs.setup }}
      GIT_CONFIG_COUNT: ${{ steps.deps-token.outputs.token != '' && '1' || '0' }}
      GIT_CONFIG_KEY_0: url.https://x-access-token:${{ steps.deps-token.outputs.token }}@github.com/.insteadOf
      GIT_CONFIG_VALUE_0: ssh://git@github.com/
    run: bash -c "$SETUP"

  - name: Revoke dependency token
    if: always() && steps.deps-token.outputs.token != ''
    env:
      GH_TOKEN: ${{ steps.deps-token.outputs.token }}
    run: gh api -X DELETE /installation/token

safe-outputs:
  create-pull-request:
    target-repo: ${{ inputs.target_repo }}
    base-branch: ${{ inputs.base_branch }}
    title-prefix: "${{ inputs.change_type }}: "
    labels: [factory]
    draft: false
    if-no-changes: error
    auto-close-issue: false
    fallback-as-issue: false
  add-comment:
    target: "*"
    required-labels: [factory:building]
---

# Build stage

Implement work item #${{ inputs.work_item }} of ${{ github.repository }} in `${{ inputs.target_repo }}`, checked out at `target/` on branch `${{ inputs.base_branch }}`.

1. Read the work item issue with the GitHub tools. Its **Specification** and **Acceptance criteria** sections are the task.
2. Do the work following your agent instructions. Run commands from `target/`. Lint command: `${{ inputs.lint }}`. Test command: `${{ inputs.test }}`. When a command is empty, find it as your instructions describe.
3. Open one pull request with `create_pull_request`:
   - Title: the work item's title as a one-line summary. The `${{ inputs.change_type }}: ` prefix is added for you.
   - Body: your Report, ending with the line `Work item: ${{ github.repository }}#${{ inputs.work_item }}`.
4. When you cannot deliver a change whose lint and tests pass, do not open a PR. Post your Report on work item #${{ inputs.work_item }} with `add_comment` instead.
