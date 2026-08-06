# Unity Cloud Build Trigger Action

## Overview

A reusable GitHub Action that triggers a [Unity Build Automation](https://docs.unity.com/en-us/build-automation) (formerly Unity Cloud Build) build for a build target, optionally on a specific branch. It returns the build ID on success.

The action does not check out or read your repository — it only calls the Unity Build Automation REST API — so it is safe to run before, after, or without `actions/checkout`.

It speaks **API v2**. Unity removes API v1 on **2026-12-21**; if you are upgrading from an earlier release of this action, see [Migrating from API v1](#migrating-from-api-v1) — the credentials change.

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
| `unity_service_account_key_id`     | Yes      | Key ID of a Unity service account with a Build Automation role.                                                                                 | —                                                        |
| `unity_service_account_secret_key` | Yes      | Secret key of that service account. Pass as a secret.                                                                                            | —                                                        |
| `branch`                           | No       | Git branch to build. When empty, the branch configured on the build target is used.                                                             | `''`                                                     |
| `clean`                            | No       | Whether to perform a clean build. Accepts `true`/`false` (also `1`/`0`, `yes`/`no`, any casing).                                                | `false`                                                  |
| `platform`                         | No       | Build platform override (e.g. `standalonewindows64`). Sent only when set.                                                                       | `''`                                                     |
| `machine_type_label`               | No       | Machine type label (e.g. `win_premium_v1`). Sent as `machineTypeLabel`, only when set.                                                          | `''`                                                     |
| `wait_for_completion`              | No       | Poll the build until it finishes and fail the step unless it succeeded. See [Waiting for the build to finish](#waiting-for-the-build-to-finish). | `false`                                                  |
| `poll_interval_seconds`            | No       | How often to poll while waiting. Values below `5` are raised to `5`.                                                                             | `30`                                                     |
| `timeout_minutes`                  | No       | Give up waiting after this many minutes and fail the step; `0` waits indefinitely. The Unity build is never canceled by this action.             | `90`                                                     |
| `api_url`                          | No       | Base URL of the API, including the version segment. v2 only — a v1 base URL is rejected.                                                         | `https://build-automation.services.api.unity.com/v2`     |

`platform` and `machine_type_label` are omitted from the request when left empty, so the build target's own configuration applies. Set them only if you want to override the target.

## Outputs

| Output               | Description                                                              |
| -------------------- | ------------------------------------------------------------------------ |
| `build_id`           | The ID (build number) of the triggered Unity build.                      |
| `platform`           | The platform of the triggered build, as reported by the API.             |
| `build_status`       | The status the build was created with (e.g. `queued`). Empty if the API did not report one. |
| `queued_reason`      | Why the build is waiting, if the API says so (e.g. `targetConcurrency`, `waitingForBuildAgent`). |
| `final_build_status` | Terminal status (`success`, `failure`, `canceled`, `unknown`). Only set when `wait_for_completion` is enabled and the build finished before the timeout. |
| `canceled_by`        | Who or what canceled the build (e.g. `concurrency-timelimit`). Only set when a waited-on build was canceled. |

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

## Waiting for the build to finish

By default the action returns as soon as Unity has accepted the build, and the
job goes green while the build is still queued. Unity can still cancel that
build afterwards — most often because it waited too long behind another build
of the same target — and nothing in the workflow will say so.

Set `wait_for_completion: true` to poll the build until it reaches a terminal
state and fail the job unless it succeeded:

```yaml
      - name: Trigger Unity Cloud Build and wait for it
        id: unity
        uses: Matuyuhi/unity-cloud-build-action@{version}
        with:
          unity_org_id: ${{ secrets.UNITY_ORG_ID }}
          unity_project_id: ${{ secrets.UNITY_PROJECT_ID }}
          build_target_id: ${{ secrets.UNITY_BUILD_TARGET_ID }}
          unity_service_account_key_id: ${{ secrets.UNITY_SA_KEY_ID }}
          unity_service_account_secret_key: ${{ secrets.UNITY_SA_SECRET_KEY }}
          wait_for_completion: true
          timeout_minutes: 120

      - name: Report
        if: always()
        run: |
          echo "final: ${{ steps.unity.outputs.final_build_status }}"
          echo "canceled by: ${{ steps.unity.outputs.canceled_by }}"
```

While waiting, each status change is logged — including the queue reason, so a
build stuck behind another one reads as `queued (targetConcurrency)` in the job
log rather than as silence. The runner is idle during the wait but still
consuming Actions minutes, so pick a `timeout_minutes` you are happy to pay for.
Giving up on the wait fails the step; it never cancels the Unity build.

The service account needs to be able to *read* builds as well as start them. If
it cannot, the step says so instead of retrying until the timeout.

## Troubleshooting

### The build shows `Canceled` with no checkout time

A build whose wait time equals its total build time, with `Checkout time
00:00:00`, no last commit and no billable time, never left the queue — it was
canceled while waiting, so nothing in the repository or the request payload
caused it. Unity *sometimes* records why in the build's `canceledBy` field,
which this action reports when `wait_for_completion` is enabled:

| `canceled_by`                | What happened                                                                 |
| ---------------------------- | ----------------------------------------------------------------------------- |
| `concurrency-timelimit`      | It waited longer than Unity allows while another build held the concurrency slot. |
| `billing-invalidsubscription`| No valid Build Automation subscription, or the build minutes ran out.          |
| `service-badconfiguration`   | Unity rejected the build target configuration.                                 |
| `service-timelimit`, `jenkins-timelimit`, `evaluation-timelimit` | A Unity-side time limit was exceeded.       |
| `restart-limit`              | The build was restarted too many times.                                        |
| `api`                        | Somebody (or something) canceled it from the dashboard or the API.             |
| `service`                    | The Build Automation service canceled it.                                      |

`canceled_by` can also be **empty**: Unity leaves `canceledBy` null for some
cancellations, including builds that are killed while waiting for a build
machine. The queue state the build was stuck in is then the only clue, which is
why `wait_for_completion` logs it on every change — `queued (waitingForBuildAgent)`
and `queued (targetConcurrency)` point at different problems.

What to look at, in order: whether another build was created for the same build
target while this one waited, whether the organization still has build minutes,
and whether the requested `machine_type_label` is one the plan can actually
provide. These endpoints answer the first and show what the build was doing:

```bash
BASE="https://build-automation.services.api.unity.com/v2/orgs/$ORG/projects/$PROJECT/buildtargets/$TARGET/builds"

curl -sS -u "$KEY_ID:$SECRET_KEY" "$BASE?per_page=10" \
  | jq '.[] | {build, buildStatus, created, finished, causedBy, canceledBy}'
curl -sS -u "$KEY_ID:$SECRET_KEY" "$BASE/$BUILD_ID" | jq .
curl -sS -u "$KEY_ID:$SECRET_KEY" "$BASE/$BUILD_ID/steps" | jq .
```

A second build created while the first was queued means two triggers are racing
for one build target — the fix below applies. A build that waited alone and was
killed anyway is a Unity-side capacity or configuration problem, not something
the workflow can fix; re-run the trigger to see whether it reproduces.

Do not bother with the `links.auditlog` URL that v2 returns inside the build
object: the endpoint it points at answers `404 Not Found` on v2, so the audit
log cannot name the canceller either.

`concurrency-timelimit` is the usual answer for release workflows: pushing a tag
and pushing to the branch often trigger two workflows within seconds of each
other, both aimed at the same build target. The second build queues behind the
first and is canceled once it has waited too long. Fixes, in order of
preference:

1. Trigger the build from one event only (for example, only on the tag push).
2. Serialise the workflows with a GitHub `concurrency` group so the second
   trigger waits for the first job instead of queueing a second Unity build.
3. Raise the concurrent build limit on the Unity organization.

## Migrating from API v1

Unity deprecated Build Automation API v1 and **removes it on 2026-12-21**. This action calls v2 and no longer supports v1, so upgrading from an earlier release is a breaking change.

| | v1 (before) | v2 (now) |
| --- | --- | --- |
| Base URL | `https://build-api.cloud.unity3d.com/api/v1` | `https://build-automation.services.api.unity.com/v2` |
| Credentials | Build Automation API key | Service account key ID + secret |
| Success status | `200`/`201` | `202 Accepted` |
| Error body | `{ "error": … }` | [RFC 7807](https://www.rfc-editor.org/rfc/rfc7807) `{ "detail": …, "requestId": … }` |

The endpoint path (`/orgs/{org}/projects/{project}/buildtargets/{target}/builds`) and the request fields this action sends (`clean`, `delay`, `branch`, `platform`, `machineTypeLabel`) are unchanged.

### What you need to change

The `authorization_header` input is **removed**. Create a [service account](#authentication) and replace it with the key pair:

```diff
-          authorization_header: ${{ secrets.UNITY_AUTH_HEADER }}
+          unity_service_account_key_id: ${{ secrets.UNITY_SA_KEY_ID }}
+          unity_service_account_secret_key: ${{ secrets.UNITY_SA_SECRET_KEY }}
```

Your old API key cannot be reused in any form — v2 only accepts service account credentials. A `403` with otherwise valid credentials usually means the service account has no Build Automation role on the project. The action calls both cases out in its error message and includes the API's `requestId`, which Unity support asks for.

Pointing `api_url` at a v1 URL fails immediately with a message telling you to pin an older release of this action, rather than sending a request that could only return `401`.

If you are not ready to create a service account, stay on the previous release of this action until you are; v1 keeps working until Unity removes it.

Reference: [Build Automation API v2](https://docs.unity.com/en-us/oas-build-automation-client/2.0.0) · [Unity's v1 → v2 migration guide](https://support.unity.com/hc/en-us/articles/51178448254356-How-do-I-migrate-my-Unity-Build-Automation-UBA-REST-API-calls-from-V1-to-V2)

## Behaviour notes

- **Non-idempotent by design.** Triggering a build is not idempotent, so a request that reached Unity is never retried. Only DNS and connection failures — where nothing reached the server — are retried (up to 3 attempts). This avoids double-charging build minutes.
- **Fire-and-forget by default.** Without `wait_for_completion`, the step succeeds once the build is queued and says so in the log; what the build does afterwards cannot affect the job. Status polling (`GET`) *is* safe to retry, so transient errors are retried up to 5 consecutive times before the wait is abandoned.
- **Secrets stay in one step.** Credentials are passed to a single step's environment and masked in the logs — the secret key, the base64 credential derived from it, and the assembled header are all masked. Nothing is written to `$GITHUB_ENV`, so they do not leak into other steps of the calling job.
- **The response body is not logged** by default. Re-run the workflow with debug logging enabled to see it.
- **Required inputs are validated before the request** — an empty org/project/target ID, a missing credential, or an invalid `clean` value fails immediately instead of producing a confusing API error.
- **A 2xx without a build ID is still a failure.** v2 can return `202` carrying only an `error` — typically because a build is already running for that target. The action reports the API's own explanation instead of an empty `build_id`. The parser accepts both the documented single-element array and a bare object.
- **`curl` and `jq`** are used, and are preinstalled on GitHub-hosted runners. On runners that lack them, the action installs them via `apt-get` or `brew`, and fails with a clear message if neither is available. `base64` (from coreutils) is also required and is present on any runner that has a shell.

## Versioning and releases

Releases are cut automatically: when a pull request is merged into `main`, the
`Release` workflow bumps the version from the latest tag, pushes the new tag and
publishes a GitHub Release with generated notes.

Three tags are published for every release, so you can choose how much movement
you accept:

| Tag form  | Example  | Moves                                            |
| --------- | -------- | ------------------------------------------------ |
| `vX.Y.Z`  | `v0.3.1` | Never — pin here for fully reproducible workflows |
| `vX.Y`    | `v0.3`   | On each patch release                            |
| `vX`      | `v0`     | On each minor and patch release                  |

While the action is on `0.x`, a minor bump may contain breaking changes, so `v0`
is the loosest possible pin. Prefer `vX.Y.Z` or `vX.Y`.

### Choosing the bump level

The level is taken from the merged pull request, in this order:

1. **Labels** (strongest wins): `release:major` / `major` / `breaking` /
   `breaking-change` → major; `release:minor` / `minor` / `feature` /
   `enhancement` → minor; `release:patch` / `patch` / `fix` / `bug` / `bugfix` →
   patch.
2. **The pull request title**, read as a [Conventional
   Commit](https://www.conventionalcommits.org/): `feat!:` or `BREAKING CHANGE`
   → major, `feat:` → minor.
3. **Patch**, as the default.

To merge without releasing, add a `release:skip` / `no-release` /
`skip-release` label, or put `[skip release]` in the pull request title.

A release can also be cut by hand from the Actions tab — run the `Release`
workflow via **Run workflow** and pick the bump level.

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
