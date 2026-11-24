# copilot-engineering-factory

Agentic factory that turns work items into pull requests on target repositories. Architecture and roadmap: [docs/strategy.md](../docs/strategy.md).

## Rules

- Write commit messages and PR titles with the Commitizen types in `.cz.toml`. The PR title becomes the squash commit.
- After editing a `.github/workflows/*.md` stage, run `gh aw compile` and commit the regenerated `.lock.yml` with it. Never edit a `.lock.yml` by hand.
- Keep routing between stages in `.github/workflows/conductor.yml`. Stages do the work and write only through safe outputs.
- Changing repo settings, the ruleset or labels: edit `scripts/repo-settings.sh`, then the matching table in `docs/setup.md`.
- Adding or changing a target: follow `docs/onboarding-a-target-repo.md`.
