---
# vim: set expandtab ft=markdown ts=4 sw=4 sts=4 tw=100:
title: MCP Service
---

# MCP Service (Model Context Protocol)

The `mcp` service exposes PlexTrac data and actions to MCP-compatible AI clients
(Claude Desktop, Cursor, etc.) over the Streamable HTTP transport. It is **off by
default** and is enabled per-instance with `MCP_REPLICAS=1`.

## Enabling MCP

Set the following in `.env`, then run `plextrac update -y`:

```bash
MCP_REPLICAS=1
PLEXTRAC_EMAIL=<email of a PlexTrac user MCP will impersonate>
PLEXTRAC_PASSWORD=<that user's password>
```

`PLEXTRAC_EMAIL` and `PLEXTRAC_PASSWORD` are **required** — MCP uses them to
authenticate against the PlexTrac API for the tool calls it makes on behalf of
the connected client. There is no fallback; the container will fail to start if
they are missing from `.env`.

The MCP service will be reachable at `https://<your-domain>/mcp`. Point your MCP
client (Cursor, Claude Desktop, etc.) at that URL.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `MCP_REPLICAS` | `0` | `1` to enable, `0` to disable. **Must be 0 or 1 — multiple replicas are not supported** (see [Why MCP is single-replica](#why-mcp-is-single-replica)). `_configure_plextrac.sh` hard-fails on any other value. |
| `MCP_LOG_LEVEL` | `INFO` | Log level for the MCP container. |
| `MCP_RATE_LIMIT_ENABLED` | `true` | Per-session and global rate limits. |
| `MCP_FAKE_AUTH` | `true` | See [auth section](#authentication). |
| `MCP_DEACTIVATE_LICENSE` | `true` | See [licensing section](#licensing). |
| `PLEXTRAC_EMAIL` | _required_ | PlexTrac user MCP authenticates as. |
| `PLEXTRAC_PASSWORD` | _required_ | That user's password. |
| `MCP_VERSION` | `0.1.0` | MCP image tag on Docker Hub. Bump in `.env` to pin a different published version. See [MCP version](#mcp-version). |
| `MCP_IMAGE` | _empty_ | Optional full image path override (e.g. `registry.example.com/cicd-app-images/mcp:0.2.0`). Takes precedence over `MCP_VERSION`. Useful for internal registry testing or customer-built images. |
| `LAUNCH_DARKLY_SDK_KEY` | _empty_ | Optional LaunchDarkly SDK key. **When empty, all MCP feature flags evaluate to True** (tools always available — the documented "inert LD client" mode in `product-services-mcp`'s `app/core/feature_flags/client.py`). When set, MCP will query LaunchDarkly per-tool and can block tools if the `MCP_SERVER` global flag is False for the evaluated context. See [Troubleshooting: tools all disabled](#troubleshooting-tools-all-disabled-by-feature-flag). |

## Authentication

MCP ≥0.0.1 dropped the legacy `API_AUTH=credential` mode for the HTTP transport.
On-prem deployments use `FAKE_AUTH=true`, which disables MCP-side authentication
entirely. Any client that can reach `/mcp` can talk to the service.

This is acceptable today because:

1. The on-prem instance is already gated behind the customer's network and TLS.
2. MCP itself authenticates outbound to the PlexTrac API using
   `PLEXTRAC_EMAIL`/`PLEXTRAC_PASSWORD`, so all data access is scoped to that
   user's permissions.
3. Keycloak — the long-term auth provider for MCP — is not yet deployable on
   on-prem instances. When it is, switch `MCP_FAKE_AUTH=false` and provide the
   `KEYCLOAK_*` variables (see [Keycloak placeholders](#keycloak-placeholders)).

!!! danger "Do NOT set `DEMO_MODE=true` on-prem"
    `DEMO_MODE` takes priority over `FAKE_AUTH` in `build_token_verifier()` and
    enables an in-memory OAuth provider that requires clients to complete a real
    OAuth 2.1 dance with PKCE. Without nginx routes for `/authorize`, `/token`,
    `/register`, and the `/.well-known/oauth-*` endpoints at the **root** of the
    domain (not under `/mcp`), this flow will fail. The k8s `aidemo` overlay
    sets both `DEMO_MODE` and `FAKE_AUTH` because it has those root-level
    ingress routes — on-prem does not.

## Licensing

`MCP_DEACTIVATE_LICENSE=true` bypasses the MCP license middleware in two places:

- The server-wide `LicenseMiddleware` is not added to the middleware stack.
- The `ClientLicenseScope` (used by `tools/clients.py` and `tools/analytics.py`)
  has `_license_keys=None`, which removes the license-key filter when listing
  clients and running analytics.

This means **any user that can reach the MCP endpoint has access to all clients
and analytics**, regardless of whether their account has the MCP license. This
is intentional for on-prem until on-prem MCP licensing exists. Set
`MCP_DEACTIVATE_LICENSE=false` once licensing is fully supported.

## Why MCP is single-replica

`MCP_REPLICAS` must be `0` (disabled) or `1` (enabled). **Never higher.**
`_configure_plextrac.sh` hard-fails if you set `MCP_REPLICAS=2` or any other
value, refusing to proceed.

MCP is a **single-process service** — one Python process with an async event
loop handling many concurrent MCP sessions in-process. It is not a
horizontally-scalable stateless web worker like `plextracapi`. Running multiple
replicas would break things in three distinct ways:

1. **Session affinity.** Each MCP client establishes a session (the
   `mcp-session-id` header) whose in-memory state lives inside a single
   process. Docker Compose's service discovery round-robins TCP connections
   across replicas with no session stickiness, so follow-up requests in a
   session would land on a replica that has no knowledge of it and return
   errors.
2. **Rate-limit counters.** `RATE_LIMIT_ENABLED=true` maintains per-session
   and global counters in process memory. Multiple replicas would each run
   their own counters, effectively multiplying the configured rate limit by
   the replica count and making the limits unenforceable.
3. **Streamable HTTP transport.** MCP's Streamable HTTP transport uses
   long-lived HTTP connections with server-sent events for responses that
   stream back over the same connection. If a client's initial `POST /mcp`
   lands on replica A and the client's follow-up `tools/call` lands on
   replica B, B has neither the session nor the streaming connection state.

If you need more MCP throughput, scale the underlying MCP process (workers
inside the container, tune `RATE_LIMIT_ENABLED`, etc.) rather than adding
replicas. This is a fundamental property of the MCP server architecture, not a
manager-util limitation.

## Nginx routing

The `plextracnginx` service mounts `${PLEXTRAC_HOME}/volumes/nginx-custom/mod_mcp_location.conf`
over `/etc/nginx/conf.d/mod_server-directive-extras.conf` inside the container.
That file is the include point for arbitrary location blocks inside the main
`server { ... }` block.

`create_volume_directories()` writes a default version of this file on first
install. It contains a `location /mcp` block that:

- Strips the `/mcp` prefix via `rewrite` (so POST bodies survive — a 301
  redirect from `/mcp` to `/mcp/` would lose the body and break the MCP
  Streamable HTTP transport).
- Proxies to `mcp:8000` with 300s timeouts for long-running tool calls.
- Disables `proxy_buffering` and sets `chunked_transfer_encoding on` for
  Server-Sent Events / streaming responses.
- Adds CORS headers for `mcp-session-id` and `mcp-protocol-version`.

You can edit `${PLEXTRAC_HOME}/volumes/nginx-custom/mod_mcp_location.conf` to
customize routing — it will not be overwritten on subsequent runs of
`plextrac configure`.

!!! note "Future: native nginx support"
    Once the `plextracnginx` image bakes in MCP routing natively (via product-deploy-manifests
    or a future stable release), the bind-mount in `static/docker-compose.yml` and
    the file generation in `_configure_plextrac.sh` can be removed.

## Keycloak placeholders

The latest ETL (3.0.0+) reads several `KEYCLOAK_*` environment variables on
plextracapi startup, even when Keycloak is not deployed. The manager-util
provides placeholder defaults so the container starts cleanly:

```bash
KEYCLOAK_INTERNAL_BASE_URL=http://keycloak.invalid
KEYCLOAK_EXTERNAL_BASE_URL=https://keycloak.invalid
KEYCLOAK_TENANT_MANAGEMENT_SERVICE_BASE_URL=http://keycloak-tms.invalid
KEYCLOAK_OIDC_BROKER_PLEXTRACAPI_INTERNAL_BASE_URL=http://plextracapi:4350
KEYCLOAK_OIDC_BROKER_CLIENT_SECRET=placeholder
KEYCLOAK_TENANT_REALM_ADMIN_CLIENT_SECRET=placeholder
KEYCLOAK_OIDC_BROKER_RSA_PRIVATE_KEY_PEM=
```

These satisfy the env var checks without pointing at a real Keycloak. Override
them in `.env` once Keycloak is available on-prem.

## Known limitations

### `plextrac/mcp` must be published to Docker Hub before MCP can be enabled

The compose definition defaults to `plextrac/mcp:${MCP_VERSION:-0.1.0}`. This
repository must exist on Docker Hub before customers can set `MCP_REPLICAS=1`
and run `plextrac update -y` successfully. Until the first publish lands:

- **Customers** cannot enable MCP via manager-util (image pull will fail).
- **Internal testers** can still exercise the branch against the Plextrac
  internal registry by setting `MCP_IMAGE` in `.env` (see
  [MCP version](#mcp-version) above for the full-image-path override pattern).

This section will be removed from Known limitations once the first tag is
published.

### No CKEditor `ckeditor-cs` alias

When testing on internal RC builds (`nginx:3.0.0-rc.3`), the nginx CKEditor
upstream was renamed from `ckeditor-backend` to `ckeditor-cs`. If you swap to an
RC nginx image manually, you will need to add a `ckeditor-cs` network alias to
the `ckeditor-backend` service in your docker-compose override:

```yaml
services:
  ckeditor-backend:
    networks:
      default:
        aliases:
        - ckeditor-cs
```

The manager-util does **not** ship this workaround in `static/docker-compose.yml`
because it tracks the `stable` nginx image, where the upstream is still
`ckeditor-backend`. Once the upstream rename lands in stable nginx (or in
product-deploy-manifests as the alias), this stops being relevant.

## MCP version

MCP releases independently of the PlexTrac platform. Unlike `plextracapi`,
`plextracnginx`, and the worker services (all of which share the platform's
`UPGRADE_STRATEGY` tag because they're built together from the same monorepo),
`plextrac/mcp` is its own image on its own release cadence. It is pinned
separately in `static/docker-compose.yml` like `plextracdb:6.5.1` and
`redis:8.4.0-alpine`, not tied to `UPGRADE_STRATEGY`.

### Version compatibility

Each manager-util release bakes in a tested, known-good `MCP_VERSION` default.
When the MCP team publishes a new version, manager-util bumps the default in
its next release.

| manager-util | bundled MCP version | tested PlexTrac platform |
| --- | --- | --- |
| 0.7.x | 0.1.0 | 2.28.x |

### Pinning a different version

Set `MCP_VERSION` in `.env` to use a different published Docker Hub tag without
waiting for a manager-util release:

```bash
MCP_VERSION=0.2.0
```

Then `plextrac update -y` to pull and recreate.

### Using a non-Docker-Hub image

For internal registry testing, customer-built images, or airgapped deployments,
set `MCP_IMAGE` in `.env`. This takes precedence over `MCP_VERSION`:

```bash
# Internal registry
MCP_IMAGE=registry.dorf.plextrac.ninja/cicd-app-images/mcp:0.1.0

# Customer-built
MCP_IMAGE=registry.customer.example/plextrac/mcp:0.1.0-custom
```

Note that pulling from a non-public registry requires the plextrac user to be
logged in first:

```bash
sudo -u plextrac docker login registry.dorf.plextrac.ninja \
  -u 'robot$gha-app-cicd-ro' -p 'YOUR_INTERNAL_REGISTRY_PASSWORD'
```

## Troubleshooting: tools all disabled by feature flag

If MCP starts cleanly and `tools/list` returns 32 tools, but every `tools/call`
returns an error like:

```
'search_clients' is currently disabled by feature flag
```

…then the `MCP_SERVER` LaunchDarkly flag is evaluating to False for the context
MCP sends (`kind=mcp-server, key=plextrac-mcp-server` under `FAKE_AUTH=true`).
The MCP container is healthy and reachable — the feature-flag decorator is
rejecting the call before the tool runs.

**Two remediation paths:**

### 1. Enable the `MCP_SERVER` flag in LaunchDarkly (recommended)

In the LaunchDarkly project whose SDK key matches your `LAUNCH_DARKLY_SDK_KEY`:

- Find the `MCP_SERVER` flag
- Either flip the global default to True, or add a targeting rule matching
  `kind=mcp-server, key=plextrac-mcp-server` (the context every on-prem MCP
  instance sends under `FAKE_AUTH=true`)

No container restart needed — LD streaming pushes the update live.

### 2. Disable LaunchDarkly for the MCP container (quick unblock)

Set `LAUNCH_DARKLY_SDK_KEY=` (empty) in `.env` or in a docker-compose override
targeting only the `mcp` service. With no SDK key, MCP's feature flag client
stays inert and every flag evaluation returns True. See
`product-services-mcp`'s `app/core/feature_flags/client.py:18-22` for the
documented "inert LD client" behavior.

Side effects: this disables LD only for the MCP container — `plextracapi`
and other services still use their own LD configuration normally. MCP will no
longer respect future per-tool feature-flag gating, but under `FAKE_AUTH=true`
there's only one effective tenant anyway, so the loss of flexibility is minimal.
