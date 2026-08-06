# Unity Cloud Build Trigger Action

## Overview

A reusable GitHub Action that triggers a [Unity Build Automation](https://docs.unity.com/en-us/build-automation) (formerly Unity Cloud Build) build for a build target, optionally on a specific branch. It returns the build ID on success.

The action does not check out or read your repository — it only calls the Unity Build Automation REST API — so it is safe to run before, after, or without `actions/checkout`.

It targets **API v2** by default. Unity removes API v1 on **2026-12-21**; see [Migrating from API v1](#migrating-from-api-v1) if you are upgrading from an earlier release of this action.

## Authentication

API v2 authenticates with HTTP Basic using a Unity **service account** key ID and secret. The legacy Build Automation API key does not work on v2.

1. In the Unity Cloud Dashboard, go to **Administration → Service Accounts** and create a service account.
2. Give it a role that allows Build Automation builds in the target project.
3. Create an API key on that service account and store the **key ID** and **secret key** as GitHub secrets.

Pass them as `unity_service_account_key_id` and `unity_service_account_secret_key`; the action base64-encodes `keyId:secretKey` and sends the `Authorization: Basic …` header for you. Both values are masked in the logs.

## Inputs

| Input                              | Required | Description                                                                                                                                     | Default                                                  |
| ---------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| `unity_org_id`                     | Yes      | The Unity Organization ID (used in the endpoint `orgs/{unity_org_id}`).                                                                         | —                                                        |
| `unity_project_id`                 | Yes      | The Unity Build Automation Project ID.                                                                                                          | —                                                        |
| `build_target_id`                  | Yes      | The Build Target ID within the Unity Build Automation project.                                                                                  | —                                                        |
| `unity_service_account_key_id`     | Yes\*    | Key ID of a Unity service account with a Build Automation role.                                                                                 | `''`                                                     |
| `unity_service_account_secret_key` | Yes\*    | Secret key of that service account. Pass as a secret.                                                                                            | `''`                                                     |
| `authorization_header`             | No\*     | Pre-built header, e.g. `Authorization: Basic <base64(keyId:secretKey)>`. A bare token also works and gets the `Authorization: ` prefix added.     | `''`                                                     |
| `branch`                           | No       | Git branch to build. When empty, the branch configured on the build target is used.                                                             | `''`                                                     |
| `clean`                            | No       | Whether to perform a clean build. Accepts `true`/`false` (also `1`/`0`, `yes`/`no`, any casing).                                                | `false`                                                  |
| `platform`                         | No       | Build platform override (e.g. `standalonewindows64`). Sent only when set.                                                                       | `''`                                                     |
| `machine_type_label`               | No       | Machine type label (e.g. `win_premium_v1`). Sent as `machineTypeLabel`, only when set.                                                          | `''`                                                     |
| `api_url`                          | No       | Base URL of the API, including the version segment.                                                                                             | `https://build-automation.services.api.unity.com/v2`     |

\* Supply **either** the service account pair **or** `authorization_header` — not both. Providing both, or only one half of the pair, fails the step before any request is sent.

`platform` and `machine_type_label` are omitted from the request when left empty, so the build target's own configuration applies. Set them only if you want to override the target.

## Outputs

| Output         | Description                                                              |
| -------------- | ------------------------------------------------------------------------ |
| `build_id`     | The ID (build number) of the triggered Unity build.                      |
| `platform`     | The platform of the triggered build, as reported by the API.             |
| `build_status` | The status the build was created with (e.g. `queued`). Empty if the API did not report one. |

## Usage

### A. PR Comment Trigger

Trigger a build when a `/build` comment is added to a pull request.

```yaml
on:
  issue_comment:
    types: [created]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    if: >
      github.event.issue.pull_request != null &&
      startsWith(github.event.comment.body, '/build')

    steps:
      - name: Trigger Unity Cloud Build
        uses: Matuyuhi/unity-cloud-build-action@{version}
        with:
          unity_org_id: ${{ secrets.UNITY_ORG_ID }}
          unity_project_id: ${{ secrets.UNITY_PROJECT_ID }}
          build_target_id: ${{ secrets.UNITY_BUILD_TARGET_ID }}
          unity_service_account_key_id: ${{ secrets.UNITY_SA_KEY_ID }}
          unity_service_account_secret_key: ${{ secrets.UNITY_SA_SECRET_KEY }}
          branch: main  # Optional: override the branch to build
```

### B. Manual Dispatch Trigger

Trigger a build manually from the Actions tab, optionally specifying a branch.

```yaml
on:
  workflow_dispatch:
    inputs:
      branch:
        description: 'Branch to build (optional)'
        required: false
      clean:
        description: 'Clean build'
        type: boolean
        default: false

permissions:
  contents: read

jobs:
  manual-build:
    runs-on: ubuntu-latest

    steps:
      - name: Trigger Unity Cloud Build manually
        id: unity
        uses: Matuyuhi/unity-cloud-build-action@{version}
        with:
          unity_org_id: ${{ secrets.UNITY_ORG_ID }}
          unity_project_id: ${{ secrets.UNITY_PROJECT_ID }}
          build_target_id: ${{ secrets.UNITY_BUILD_TARGET_ID }}
          unity_service_account_key_id: ${{ secrets.UNITY_SA_KEY_ID }}
          unity_service_account_secret_key: ${{ secrets.UNITY_SA_SECRET_KEY }}
          branch: ${{ inputs.branch }}
          clean: ${{ inputs.clean }}

      - name: Use the outputs
        run: |
          echo "Build ${{ steps.unity.outputs.build_id }} started"
          echo "Platform: ${{ steps.unity.outputs.platform }}"
          echo "Status: ${{ steps.unity.outputs.build_status }}"
```

## Migrating from API v1

Unity deprecated Build Automation API v1 and **removes it on 2026-12-21**. This action calls v2 by default. If you used an earlier release, two things change in your workflow:

| | v1 (before) | v2 (now) |
| --- | --- | --- |
| Base URL | `https://build-api.cloud.unity3d.com/api/v1` | `https://build-automation.services.api.unity.com/v2` |
| Credentials | Build Automation API key | Service account key ID + secret |
| Success status | `200`/`201` | `202 Accepted` |
| Error body | `{ "error": … }` | [RFC 7807](https://www.rfc-editor.org/rfc/rfc7807) `{ "detail": …, "requestId": … }` |

The endpoint path (`/orgs/{org}/projects/{project}/buildtargets/{target}/builds`) and the request fields this action sends (`clean`, `delay`, `branch`, `platform`, `machineTypeLabel`) are unchanged.

To migrate, replace the `authorization_header` input with the service account pair:

```diff
-          authorization_header: ${{ secrets.UNITY_AUTH_HEADER }}
+          unity_service_account_key_id: ${{ secrets.UNITY_SA_KEY_ID }}
+          unity_service_account_secret_key: ${{ secrets.UNITY_SA_SECRET_KEY }}
```

Reusing your old API key will fail with `HTTP 401`/`403` — v2 only accepts service account credentials. A `403` with valid credentials usually means the service account has no Build Automation role on the project. The action calls both cases out explicitly in its error message and includes the API's `requestId`, which Unity support asks for.

### Staying on v1 temporarily

Point `api_url` back at v1 until you have a service account in place. The action logs a deprecation warning when you do:

```yaml
        with:
          api_url: https://build-api.cloud.unity3d.com/api/v1
          authorization_header: ${{ secrets.UNITY_AUTH_HEADER }}
          # ...
```

Both versions are parsed by the same code: the response parser accepts a single-element array (`[{ "build": 123, … }]`) or a bare object, and reads error text from `detail`, `error`, `message`, or `title`, whichever the response carries. If a response has no build ID, the action fails with the API's own explanation (e.g. a build is already running for that target) rather than silently reporting an empty one.

Reference: [Build Automation API v2](https://docs.unity.com/en-us/oas-build-automation-client/2.0.0) · [Unity's v1 → v2 migration guide](https://support.unity.com/hc/en-us/articles/51178448254356-How-do-I-migrate-my-Unity-Build-Automation-UBA-REST-API-calls-from-V1-to-V2)

## Behaviour notes

- **Non-idempotent by design.** Triggering a build is not idempotent, so a request that reached Unity is never retried. Only DNS and connection failures — where nothing reached the server — are retried (up to 3 attempts). This avoids double-charging build minutes.
- **Secrets stay in one step.** Credentials are passed to a single step's environment and masked in the logs — the secret key, the base64 credential derived from it, and the assembled header are all masked. Nothing is written to `$GITHUB_ENV`, so they do not leak into other steps of the calling job.
- **The response body is not logged** by default. Re-run the workflow with debug logging enabled to see it.
- **Required inputs are validated before the request** — an empty org/project/target ID, a missing or ambiguous credential, or an invalid `clean` value fails immediately instead of producing a confusing API error.
- **`curl` and `jq`** are used, and are preinstalled on GitHub-hosted runners. On runners that lack them, the action installs them via `apt-get` or `brew`, and fails with a clear message if neither is available. `base64` (from coreutils) is also required and is present on any runner that has a shell.

## Development

Validate `action.yml` and the shell scripts embedded in it:

```bash
./scripts/lint-action.sh
```

This checks that the file parses, that each declared output points at a real step ID, that no input is interpolated directly into a `run:` block (a script-injection vector), and that every embedded script passes `bash -n` and `shellcheck`. It runs in CI on every push and pull request.

## License

MIT License

---

For implementation details, see `action.yml`.
