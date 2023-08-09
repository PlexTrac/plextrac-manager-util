# Release Management

The `bumpversion` Python CLI tool is used to manage tags for this project. Automation is not yet in
place to automatically create a release when a new tag is created, so releasing is a two step
process:

1. Version Bump
2. Create Release

When the release is created, GitHub workflows kick off a job to build and attach the CLI to the
GitHub release as an attachment. It will then be available the next time an instance self-updates.

## Version Bump

Make sure you have the Python `bumpversion` package installed. **Only version bump from `main`!!!**.
`bumpversion` is SemVer aware, so you can just `bumpversion patch` or `bumpversion minor` from the
repository root. A new commit & tag will be created, which you can then push to GitHub via `git push
&& git push --tags`.

The configuration for `bumpversion` lives at `.bumpversion.cfg`, and it contains the current semver
as well as a reference to any other files to check and update the version when performing a version
bump. Basically it just figures out the next semver and does the equivalent of `sed 's/<old
version>/<new version>/g'`, then commits and creates a tag with the new semver.

## Releases

Always create a release from a tag created by `bumpversion`. If you wish to test the release prior
to making it fully available to all consumers, mark it as a pre-release (or just uncheck
**latest**). Then use the `PLEXTRAC_UTILITY_VERSION` envvar to pin your test environment to the
desired release. Once satisfied, just edit the release and mark it as latest. Voila! Everyone will
pull that on their next update.

