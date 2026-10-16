# Setup BCQuality

Installs the BCQuality marketplace plugin, physically filters its installed
content to the requested policy, and regenerates its knowledge index before an
AL-Go feature invokes Copilot.

The action changes the local Copilot plugin installation, so it runs only on
temporary GitHub-hosted runners. It does not run on self-hosted runners.

```yaml
- name: Setup BCQuality
  id: bcquality
  uses: microsoft/AL-Go-Actions/SetupBCQuality@main

- name: Run a BCQuality-backed feature
  shell: pwsh
  env:
    BCQUALITY_PLUGIN_ROOT: ${{ steps.bcquality.outputs.pluginRoot }}
  run: ./Run-Feature.ps1
```

The marketplace ref selects the BCQuality release. The action discovers the
installed plugin version from its manifest and retains all content layers by
default. When `marketplaceRef` is omitted, the action uses the centralized
`BCQuality.version` default from AL-Go's settings module.

The installed plugin is available only to later steps in the same job. A
different job or workflow receives a new runner and must run the action again:

```yaml
jobs:
  another-agent:
    runs-on: windows-latest
    steps:
      - name: Setup BCQuality
        id: bcquality
        uses: microsoft/AL-Go-Actions/SetupBCQuality@main

      - name: Run another BCQuality-backed agent
        shell: pwsh
        env:
          BCQUALITY_PLUGIN_ROOT: ${{ steps.bcquality.outputs.pluginRoot }}
        run: ./Run-AnotherAgent.ps1
```

`marketplaceRef` should be a BCQuality release tag. Branch refs are supported
only for prototype testing because they can move between runs.

The Copilot PR Review runner maps the top-level `BCQuality` setting to this
action through `bcqualitySettingsJson`. Marketplace selection, plugin identity,
layer and skill filtering, knowledge filtering, and task context therefore
share one repository settings surface. The runner passes this action's
`pluginRoot` output to `ReviewAgent`; the review action does not install
BCQuality.

JSON arrays are preserved as supplied, including commas in skill paths or
knowledge patterns. Only the standalone `enabledLayers`, `disabledSkills`,
`knowledgeAllow`, and `knowledgeDeny` inputs use comma-separated values.
An empty `BCQuality.enabledLayers` array retains all three content layers.

For a private marketplace repository, pass a token with read access through
the `token` input. Authentication is applied only to the Git and Copilot CLI
child processes that resolve and install a non-default marketplace. The
default `microsoft/BCQuality` marketplace always uses the public
unauthenticated flow. The token is not written to Git configuration or
retained after the action completes.
