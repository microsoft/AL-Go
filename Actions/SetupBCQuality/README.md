# Setup BCQuality

Installs the BCQuality marketplace plugin, physically filters its installed
content to the requested policy, and regenerates its knowledge index before an
AL-Go feature invokes Copilot.

The action mutates Copilot's default installed-plugin directory and therefore
supports only ephemeral GitHub-hosted runners. It fails closed on self-hosted
runners.

```yaml
- name: Setup BCQuality
  id: bcquality
  uses: microsoft/AL-Go-Actions/SetupBCQuality@main
  with:
    marketplaceRef: v1.7
    expectedPluginVersion: 0.2.0
    enabledLayers: microsoft

- name: Run a BCQuality-backed feature
  shell: pwsh
  env:
    BCQUALITY_PLUGIN_ROOT: ${{ steps.bcquality.outputs.pluginRoot }}
  run: ./Run-Feature.ps1
```

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

`marketplaceRef` should be an immutable BCQuality release tag. Branch refs are
supported only for prototype testing because they can move between runs.

For a private marketplace repository, pass a token with read access through
the `token` input. Authentication is applied only to the Git and Copilot CLI
child processes that resolve and install a non-default marketplace. The
default `microsoft/BCQuality` marketplace always uses the public
unauthenticated flow. The token is not written to Git configuration or
retained after the action completes.
