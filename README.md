# publish-ruby-gem

Release your Ruby Gem to GitHub Packages with ease. This action is a fast, lightweight composite action that defaults to **Ruby 4.0**.

## Why use this?

- **Fast:** Composite action runs directly on the host, avoiding Docker overhead.
- **Simple:** No complex configuration needed.
- **Modern:** Defaults to Ruby 4.0 but supports any version via input.

## Usage

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build and publish to GitHub Packages
        uses: actionshub/publish-ruby-gem@main
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `token` | **Required** GitHub token with write access to packages. | N/A |
| `owner` | Name of the user or organization account. | `${GITHUB_REPOSITORY_OWNER}` |
| `working-directory` | Path to switch to before building the Gem. | `.` |
| `ruby-version` | Ruby version to use for build/push. | `4.0` |

## Credits

This Action has been heavily influenced by [Jstastny's Publish-Gem-to-Github Action](https://github.com/jstastny/publish-gem-to-github).
