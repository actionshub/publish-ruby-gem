# publish-ruby-gem

Release Ruby gems to GitHub Packages, RubyGems.org, Gem.coop, Forgejo, and Gitea from a single fast composite action.

This is the preferred Actionshub path for publishing Ruby gems. It runs directly on the GitHub runner, masks supplied tokens, fails when build or push commands fail, and writes a short publish summary to the job summary.

## Usage

```yaml
name: release

on:
  push:
    branches: [main]

permissions:
  contents: read
  packages: write

jobs:
  release:
    runs-on: ubuntu-slim
    steps:
      - name: Checkout
        uses: actions/checkout@v6.0.3

      - name: Build and publish to multiple registries
        uses: actionshub/publish-ruby-gem@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          rubygems_token: ${{ secrets.RUBYGEMS_AUTH_TOKEN }}
          gemcoop_token: ${{ secrets.GEMCOOP_AUTH_TOKEN }}
          forgejo_token: ${{ secrets.FORGEJO_TOKEN }}
          forgejo_url: https://forgejo.example.com
          gitea_token: ${{ secrets.GITEA_TOKEN }}
          gitea_url: https://gitea.example.com
```

Only provide tokens for the registries you want to publish to.

### RubyGems.org only

```yaml
- name: Build and publish to RubyGems.org
  uses: actionshub/publish-ruby-gem@main
  with:
    rubygems_token: ${{ secrets.RUBYGEMS_AUTH_TOKEN }}
```

### GitHub Packages only

```yaml
permissions:
  contents: read
  packages: write

steps:
  - name: Build and publish to GitHub Packages
    uses: actionshub/publish-ruby-gem@main
    with:
      github_token: ${{ secrets.GITHUB_TOKEN }}
```

### Forgejo only

```yaml
- name: Build and publish to Forgejo
  uses: actionshub/publish-ruby-gem@main
  with:
    forgejo_token: ${{ secrets.FORGEJO_TOKEN }}
    forgejo_url: https://forgejo.example.com
    forgejo_owner: my-org
```

Forgejo publishes to `https://forgejo.example.com/api/packages/{owner}/rubygems`.

### Gitea only

```yaml
- name: Build and publish to Gitea
  uses: actionshub/publish-ruby-gem@main
  with:
    gitea_token: ${{ secrets.GITEA_TOKEN }}
    gitea_url: https://gitea.example.com
    gitea_owner: my-org
```

Gitea publishes to `https://gitea.example.com/api/packages/{owner}/rubygems`.

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `github_token` | Token for GitHub Packages. | N/A |
| `rubygems_token` | API key for RubyGems.org. | N/A |
| `gemcoop_token` | API key for Gem.coop. | N/A |
| `forgejo_token` | Personal access token for a Forgejo RubyGems package registry. | N/A |
| `forgejo_url` | Base URL for the Forgejo instance. Required when `forgejo_token` is set. | N/A |
| `forgejo_owner` | User or organization account for the Forgejo package. | `owner`, then `${GITHUB_REPOSITORY_OWNER}` |
| `gitea_token` | Personal access token for a Gitea RubyGems package registry. | N/A |
| `gitea_url` | Base URL for the Gitea instance. Required when `gitea_token` is set. | N/A |
| `gitea_owner` | User or organization account for the Gitea package. | `owner`, then `${GITHUB_REPOSITORY_OWNER}` |
| `token` | Alias for `github_token`. | N/A |
| `owner` | User or organization account for GitHub Packages. | `${GITHUB_REPOSITORY_OWNER}` |
| `working-directory` | Path to switch to before building the gem. | `.` |
| `ruby-version` | Ruby version to use for build and push. | `4.0` |

## Outputs

| Output | Description |
|--------|-------------|
| `completed` | `true` when every configured publish completes successfully. Failure paths emit `false` before exiting. |
| `version` | Unique published gem version, or comma-separated versions when multiple gemspecs produce different versions. |
| `releases` | JSON array of built releases. Each entry includes `name`, `version`, `file`, and `registries`. |

Example `releases` value:

```json
[{"name":"my-gem","version":"1.2.3","file":"my-gem-1.2.3.gem","registries":["RubyGems.org","GitHub Packages"]}]
```

## Behavior

- At least one registry token is required.
- Forgejo and Gitea require their matching `*_url` input when their token is set.
- The action builds top-level `*.gemspec` files in the working directory.
- Only gems built during the current action run are pushed.
- Failed builds and failed pushes stop the action with a GitHub Actions error annotation.
- Token values are masked before any publish work starts.
- `jq` is required for structured outputs. GitHub-hosted Ubuntu runners, including `ubuntu-slim`, include `jq`; self-hosted runners must provide it.

## Credits

This Action has been heavily influenced by [Jstastny's Publish-Gem-to-Github Action](https://github.com/jstastny/publish-gem-to-github).
