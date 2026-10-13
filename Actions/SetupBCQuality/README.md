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

`marketplaceRef` should be an immutable BCQuality release tag. Branch refs are
supported only for prototype testing because they can move between runs.

For a private marketplace repository, pass a token with read access through
the `token` input. Authentication is provided to Git and Copilot only through
temporary process-scoped Git configuration and is not persisted in a checkout
or artifact.
