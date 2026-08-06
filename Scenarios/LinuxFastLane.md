# Linux fast lane for pull request builds

Pull request builds on the standard AL-Go pipeline spin up a full Windows BC
container and go through the complete compile/sign/test/analyze chain. That
is correct and necessary as the final gate on `main`, but it's slow and
costly to run on every push to every pull request.

The `linuxFastLane` setting builds a project using
[StefanMaron/MsDyn365Bc.On.Linux](https://github.com/StefanMaron/MsDyn365Bc.On.Linux)
(bc-linux) instead: it compiles AL source, publishes to a BC service tier
running on Linux via Docker Compose, and runs AL unit tests - entirely on an
`ubuntu-latest` runner, no Windows container involved. It's meant as a fast,
cheap gate for pull requests (and optionally a dedicated test branch), not a
replacement for the full pipeline on `main`.

## Enabling it

Set the `linuxFastLane` setting to `true`. Combine it with AL-Go's existing
[ConditionalSettings](settings.md#conditional) mechanism to scope it to
specific branches or workflows, for example:

```json
"ConditionalSettings": [
  {
    "workflows": ["PullRequestHandler"],
    "settings": { "linuxFastLane": true }
  },
  {
    "branches": ["test", "test/*"],
    "workflows": ["CICD"],
    "settings": { "linuxFastLane": true }
  }
]
```

BC version and country come from the project's existing `artifact` and
`country` settings - there's nothing new to configure there. If `artifact`
can't be resolved to a concrete version (for example when it's left as
`latest`), the fast lane falls back to bc-linux's own default version and
logs a warning; pin `artifact` to a concrete version for predictable
results.

## What's in scope

- Compiling AL apps from source (production and test apps)
- Publishing to a Linux BC container and running AL unit tests, with JUnit
  results uploaded as a workflow artifact
- Both single-project and multi-project repositories (projects are matrixed
  the same way as the standard `Build` job)

## What's out of scope

- **Code signing.** The fast lane never calls the `Sign` action.
- **BCPT (performance) tests, page scripting (browser) tests, PowerPlatform
  solution builds, and Deliver** (to AppSource / GitHub Packages / storage).
  None of these run on this path.
- **AL Code Analysis / SARIF upload.** `CodeAnalysisUpload` only processes
  output from the standard Windows build.
- **A small number of AL tests are known to fail on Linux BC.** See
  bc-linux's
  [`KNOWN-LIMITATIONS.md`](https://github.com/StefanMaron/MsDyn365Bc.On.Linux/blob/master/KNOWN-LIMITATIONS.md)
  for the current list (for example, tests that unconditionally delete the
  active session's user, or tests that require a UI context for controls
  like Camera/Barcode Scanner). These will show up red in the fast lane;
  this is expected, not a regression.

## `main` stays on the standard pipeline

`main` is not expected to use `linuxFastLane` - it should keep running the
full, Microsoft-supported Windows pipeline (signing, BCPT, page scripting,
Deliver) as the final gate before a release.
