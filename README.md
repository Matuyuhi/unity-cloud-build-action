# Unity Cloud Build Trigger Action

## Overview

A reusable GitHub Action that triggers a Unity Cloud Build for a specified commit SHA or branch. It returns the build ID upon success.

## Inputs

| Input                  | Required | Description                                                                                         | Default               |
| ---------------------- | -------- | --------------------------------------------------------------------------------------------------- | --------------------- |
| `unity_org_id`         | Yes      | The Unity Organization ID (used in the endpoint `orgs/{unity_org_id}`).                             | —                     |
| `unity_project_id`     | Yes      | The Unity Cloud Build Project ID.                                                                   | —                     |
| `build_target_id`      | Yes      | The Build Target ID within the Unity Cloud Build project.                                           | —                     |
| `authorization_header` | Yes      | Authorization header for the Unity Cloud Build API (e.g., `Authorization: Basic ...`).              | —                     |
| `commit_sha`           | No       | The commit SHA to build. If not provided, the action uses the `branch` input or the current `HEAD`. | (empty)               |
| `branch`               | No       | The Git branch to build. If provided, the latest commit SHA from this branch will be fetched.       | (empty)               |
| `clean`                | No       | Whether to perform a clean build (`true` or `false`).                                               | `false`               |
| `platform`             | No       | The build platform (e.g., `standalonewindows64`).                                                   | `standalonewindows64` |
| `machine_type_label`   | No       | Machine type label for the build machine (e.g., `win_premium_v1`).                                  | `win_premium_v1`      |

## Outputs

| Output     | Description                                |
| ---------- | ------------------------------------------ |
| `build_id` | The ID of the triggered Unity Cloud Build. |

## Usage

### A. PR Comment Trigger

Trigger a build when a `/build` comment is added to a pull request.

```yaml
on:
  issue_comment:
    types: [created]

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
          branch: main  # Optional: override branch to build
```

### B. Manual Dispatch Trigger

Trigger a build manually from the Actions tab, optionally specifying `commit_sha` or `branch`.

```yaml
on:
  workflow_dispatch:
    inputs:
      commit_sha:
        description: 'Commit SHA to build (optional)'
        required: false
      branch:
        description: 'Branch to build (optional)'
        required: false

jobs:
  manual-build:
    runs-on: ubuntu-latest

    steps:
      - name: Trigger Unity Cloud Build manually
        uses: Matuyuhi/unity-cloud-build-action@{version}
        with:
          unity_org_id: ${{ secrets.UNITY_ORG_ID }}
          unity_project_id: ${{ secrets.UNITY_PROJECT_ID }}
          build_target_id: ${{ secrets.UNITY_BUILD_TARGET_ID }}
          authorization_header: ${{ secrets.UNITY_AUTH_HEADER }}
          commit_sha: ${{ github.event.inputs.commit_sha }}
          branch: ${{ github.event.inputs.branch }}
```

## License

MIT License

---

For implementation details, see `action.yml`.
