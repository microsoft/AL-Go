# Linux fast lane for pull request and CI/CD builds

Pull request and CI/CD builds on the standard AL-Go pipeline spin up a full
Windows BC container and go through the complete compile/sign/test/analyze
chain. That is correct and necessary as the final gate on `main`, but it's
slow and costly to run on every push to every pull request or test branch.

The `linuxFastLane` setting builds a project using
[StefanMaron/MsDyn365Bc.On.Linux](https://github.com/StefanMaron/MsDyn365Bc.On.Linux)
(bc-linux) instead: it compiles AL source, publishes to a BC service tier
running on Linux via Docker Compose, and runs AL unit tests - entirely on an
`ubuntu-latest` runner, no Windows container involved. It's wired into both
`PullRequestHandler` (pull request builds) and `CICD` (regular push and
manual-dispatch builds), so it works the same way whether the build was
triggered by a PR or a push. It's meant as a fast, cheap gate for pull
requests and non-production branches (a dedicated test branch, for example),
not a replacement for the full pipeline on `main`.

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

The AL compiler is chosen the same way as on the Windows pipeline, via the
project's existing [`vsixFile`](settings.md#vsixFile) setting:

| `vsixFile` | Linux fast lane compiler policy |
| --- | --- |
| `default` (or unset) | matching - newest stable AL compiler for the BC major being built (bc-linux's own default) |
| `latest` | newest stable AL compiler across all majors |
| `preview` | newest AL compiler across all majors, including prereleases |
| a direct download URL | can't be mapped to a policy keyword - falls back to `default`/matching, with a warning |

This matters because the AL compiler version and the BC runtime version are
independent: a newer compiler accepts older runtimes, but the reverse isn't
guaranteed. A project whose Windows pipeline uses `vsixFile: latest` should
generally use the same policy here to avoid the fast lane rejecting AL that
the Windows build accepts (or vice versa).

## What's in scope

- Compiling AL apps from source (production and test apps)
- Publishing to a Linux BC container and running AL unit tests, with JUnit
  results uploaded as a workflow artifact
- Both single-project and multi-project repositories (projects are matrixed
  the same way as the standard `Build` job)
- Same-repo project dependencies (one project in the repo depending on
  another). The dependency project's production app is resolved the same way
  the standard `Build` job resolves it - from this workflow run if that
  project was also built here, otherwise from the last successful baseline
  build - and staged alongside any third-party (`appDependencyProbingPaths`)
  dependency apps.
- Compiled Apps/TestApps published as AL-Go-named artifacts (same naming
  `CalculateArtifactNames` gives the standard `Build` job), via a
  `PublishLinuxArtifacts` job that re-shapes the plain artifact bc-linux
  uploads. This is what lets `Deploy`/`Deliver` find and use a Linux fast
  lane project's apps exactly like they find `Build`'s.

## What's out of scope

- **Code signing.** The fast lane never calls the `Sign` action.
- **BCPT (performance) tests, page scripting (browser) tests, and
  PowerPlatform solution builds.** None of these run on this path.
- **AL Code Analysis / SARIF upload.** `CodeAnalysisUpload` only processes
  output from the standard Windows build.
- **A small number of AL tests are known to fail on Linux BC.** See
  bc-linux's
  [`KNOWN-LIMITATIONS.md`](https://github.com/StefanMaron/MsDyn365Bc.On.Linux/blob/master/KNOWN-LIMITATIONS.md)
  for the current list (for example, tests that unconditionally delete the
  active session's user, or tests that require a UI context for controls
  like Camera/Barcode Scanner). These will show up red in the fast lane;
  this is expected, not a regression.

## Compile-only projects are never routed to the fast lane

The fast lane always publishes apps to its Linux container and runs tests
there. A project set up to compile without publishing anything - `useCompilerFolder: true`
(no container at all) or `doNotPublishApps: true` - has nothing for that to
do, so `linuxFastLane` is ignored for it and it keeps building on the
standard Windows pipeline instead, with a warning in the log. This matters
for org- or repo-wide `linuxFastLane: true` defaults: turning it on globally
does not break a project that's deliberately compile-only, for example one
whose apps depend on AppSource apps that can only be compiled against, not
installed for testing.

## `main` stays on the standard pipeline

`main` is not expected to use `linuxFastLane` - it should keep running the
full, Microsoft-supported Windows pipeline (signing, BCPT, page scripting,
Deliver) as the final gate before a release. `PullRequestHandler` and `CICD`
both have a job that runs the fast lane; scope it away from `main` with
[ConditionalSettings](settings.md#conditional) (for example, gate it on
`branches` other than `main`, as in the example above). `CreateRelease` and
every other workflow ignore `linuxFastLane` and always use the standard
pipeline, even if it's set (directly, or via a broad repo/org default).
A project doesn't disappear from those builds because of it.
