# Unity Cloud Build Trigger Action

## Overview

A reusable GitHub Action that triggers a [Unity Build Automation](https://docs.unity.com/en-us/build-automation) (formerly Unity Cloud Build) build for a build target, optionally on a specific branch. It returns the build ID on success.

The action does not check out or read your repository — it only calls the Unity Build Automation REST API — so it is safe to run before, after, or without `actions/checkout`.

## Inputs

| Input                  | Required | Description                                                                                                                                     | Default                                          |
| ---------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `unity_org_id`         | Yes      | The Unity Organization ID (used in the endpoint `orgs/{unity_org_id}`).                                                                         | —                                                |
| `unity_project_id`     | Yes      | The Unity Build Automation Project ID.                                                                                                          | —                                                |
| `build_target_id`      | Yes      | The Build Target ID within the Unity Build Automation project.                                                                                  | —                                                |
| `authorization_header` | Yes      | Authorization header for the API, e.g. `Authorization: Basic <token>`. A bare token is also accepted and gets the `Authorization: ` prefix added. | —                                                |
| `branch`               | No       | Git branch to build. When empty, the branch configured on the build target is used.                                                             | `''`                                             |
| `clean`                | No       | Whether to perform a clean build. Accepts `true`/`false` (also `1`/`0`, `yes`/`no`, any casing).                                                | `false`                                          |
| `platform`             | No       | Build platform override (e.g. `standalonewindows64`). Sent only when set.                                                                       | `''`                                             |
| `machine_type_label`   | No       | Machine type label (e.g. `win_premium_v1`). Sent as `machineTypeLabel`, only when set.                                                          | `''`                                             |
| `api_url`              | No       | Base URL of the API, including the version segment. Override to target a newer API version.                                                     | `https://build-api.cloud.unity3d.com/api/v1`     |

`platform` and `machine_type_label` are omitted from the request when left empty, so the build target's own configuration applies. Set them only if you want to override the target.

## Outputs

| Output     | Description                                              |
| ---------- | -------------------------------------------------------- |
| `build_id` | The ID (build number) of the triggered Unity build.      |
| `platform` | The platform of the triggered build, as reported by the API. |

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
          authorization_header: ${{ secrets.UNITY_AUTH_HEADER }}
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
          authorization_header: ${{ secrets.UNITY_AUTH_HEADER }}
          branch: ${{ inputs.branch }}
          clean: ${{ inputs.clean }}

      - name: Use the outputs
        run: |
          echo "Build ${{ steps.unity.outputs.build_id }} started"
          echo "Platform: ${{ steps.unity.outputs.platform }}"
```

## API version

By default the action calls API **v1** at `https://build-api.cloud.unity3d.com/api/v1`, which is the version Unity's published Build Automation API reference documents.

If you are moving to a newer API version, point `api_url` at it — no change to the action is needed as long as the request/response shapes stay compatible:

```yaml
        with:
          api_url: https://build-api.cloud.unity3d.com/api/v2
          # ...
```

The response parser accepts both a single-element array (`[{ "build": 123, ... }]`, the v1 shape) and a bare object (`{ "build": 123, ... }`). If a newer version renames the `build` field, the action fails with the raw response body rather than silently reporting an empty build ID.

## Behaviour notes

- **Non-idempotent by design.** Triggering a build is not idempotent, so a request that reached Unity is never retried. Only DNS and connection failures — where nothing reached the server — are retried (up to 3 attempts). This avoids double-charging build minutes.
- **Secrets stay in one step.** The authorization header is passed to a single step's environment and masked in the logs. It is not written to `$GITHUB_ENV`, so it does not leak into other steps of the calling job.
- **The response body is not logged** by default. Re-run the workflow with debug logging enabled to see it.
- **Required inputs are validated before the request** — an empty org/project/target ID or an invalid `clean` value fails immediately instead of producing a confusing API error.
- **`curl` and `jq`** are used, and are preinstalled on GitHub-hosted runners. On runners that lack them, the action installs them via `apt-get` or `brew`, and fails with a clear message if neither is available.

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
