# publish-gem-to-github

Release your Ruby Gem to GitHub Packages, RubyGems.org, and Gem.coop with ease. This action is a fast, lightweight composite action that defaults to **Ruby 4.0**.

## Why use this?

- **Fast:** Composite action runs directly on the host, avoiding Docker overhead.
- **Multi-Registry:** Support for GitHub Packages, RubyGems.org, and Gem.coop.
- **Simple:** Just add your API keys to enable pushing to each registry.
- **Modern:** Defaults to Ruby 4.0 but supports any version via input.

## Usage

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build and publish to multiple registries
        uses: actionshub/publish-ruby-gem@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          rubygems_token: ${{ secrets.RUBYGEMS_AUTH_TOKEN }}
          gemcoop_token: ${{ secrets.GEMCOOP_AUTH_TOKEN }}
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `github_token` | Token for GitHub package registry. | N/A |
| `rubygems_token` | API key for RubyGems.org. | N/A |
| `gemcoop_token` | API key for Gem.coop. | N/A |
| `token` | Alias for `github_token`. | N/A |
| `owner` | Name of the user or organization account for GitHub Packages. | `${GITHUB_REPOSITORY_OWNER}` |
| `working-directory` | Path to switch to before building the Gem. | `.` |
| `ruby-version` | Ruby version to use for build/push. | `4.0` |

## Credits

This Action has been heavily influenced by [Jstastny's Publish-Gem-to-Github Action](https://github.com/jstastny/publish-gem-to-github).
