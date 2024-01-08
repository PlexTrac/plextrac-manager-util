# Contiguous Updates

As of version v2.0 of PlexTrac and to support further migration efforts away from Couchbase, a request was made to support a model of updating versions contiguously (serially) starting at the update from `2.0` to `2.1`. The `_version_check.sh` file was created and the `_update.sh` was extended to support this. Some details on testing and how it works are written out below.

## How it works

When an update is called via `plextrac update`, the version_check function happens and validates the following:

- What version of plextrac is currently running?
- What is the breaking version? (This is staticly set to version 2.0)
- What is the current version of PlexTrac that is available?
- Is a contiguous update needed or can we update normally?
- If we do a contiguous update, what is the upgrade path and how long will it take?

The function gets answers to all these questions and then proceeds with updating in 1 of 2 ways:

- Normal Update (functions like it has historically)
- Contiguous Update (Updates Contiguously beginning at the breaking version)

Example:

Customer Axolotl is currently running version `v1.58.X` and runs an update. The util knows they are running `v1.58.X` and also knows that the `breaking version` is set to `v2.0.X`. The current available version of PlexTrac in this example is `v2.5.X`. The update will happen in the following order:

- Update `v1.58.X` --> `v2.0.X`
- Update `v2.0.X` --> `v2.1.X`, then `v2.2.X`, etc to `v2.5.X`

## Testing

> You  can manually set the `breaking_version` variable in the `version_check()` function to a lower number (like `v.1.59`) and then set your test environment's running version of PlexTrac to a previous version to that (`v1.57`) and watch it jump to the `breaking_version` value, then contiguously update to the current version of PlexTrac.

## BETA Testing

If you want to use this functionality prior to its full release, you can add the `SKIP_SELF_UPGRADE=1` and `PLEXTRAC_UTILITY_VERSION=v0.5.1-beta` to get the fucntionality early.
