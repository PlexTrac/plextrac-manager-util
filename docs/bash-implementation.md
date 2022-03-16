# BASH Implementation Details


## Release

> #TODO: Any PR to main should trigger a release. Default to `patch`, but use
  labels to handle `minor` as well. Major should be pretty explicitly managed.

Upon release, files matching the glob `_*.sh` are concatenated together with the
`/src/plextrac` main script.  `/static/docker-compose.yml` and
`/static/docker-compose.override.yml` are each `base64` encoded and embedded in
the same output file.  This file should be attached to the GitHub release in
order to permit auto-updating clients.

## Structure

`/src`
:   All source code resides here. Please name functions sensibly and understand
    that all files share a common namespace. Related functionality is organized
    into multiple files only for convenience and ease of understanding.

`/static`
:   The `docker-compose.yml` and default `docker-compose.override.yml` files are
    available under the `/static` directory. The override file is intended only as
    an example; do not rely on it being up to date on the target system!

`/docs`
:   All documentation should reside here. MkDocs is used to generate HTML content
    that is integrated with our internal documentation at https://docs.plextrac.ninja
