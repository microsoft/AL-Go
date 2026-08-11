# Getting symbols from NuGet instead of from an artifact

When AL-Go compiles without a container it first builds a *compiler folder*: the AL
compiler, the built-in analyzers, and the Microsoft symbols your apps compile against.
By default that folder is populated from a Business Central artifact.

Setting [symbolsSource](settings.md#symbolsSource) to `nuGet` populates it from
Microsoft's public NuGet feeds instead. No artifact is downloaded.

```json
{
  "workspaceCompilation": { "enabled": true },
  "symbolsSource": "nuGet"
}
```

## Why

An artifact is a complete Business Central deployment: the service tier, the web client,
a demo database, help files. A compile needs a few megabytes of that.

| | artifact | NuGet |
|---|---|---|
| downloaded | ~2.2 GB of zips | ~23 MB |
| extracted | ~3.1 GB, thousands of files | ~53 MB |
| symbols staged | every app in the artifact | only the dependency closure |

The app artifact is dominated by a ~900 MB `BusinessCentral-*.bak` that a compile-only
build never opens.

## Where the pieces come from

- **Symbols** - the `MSSymbols` feed. The build's country and version come from the
  resolved `artifact` setting exactly as before, so pinning `artifact` still pins what
  you compile against. `Microsoft.Application.<COUNTRY>.symbols` declares its own
  dependency closure - System Application, Business Foundation, Base Application,
  Platform - and that closure is walked rather than assumed.
- **Microsoft app dependencies** - anything your `app.json` files declare with publisher
  `Microsoft` is resolved as
  `Microsoft.<AppNameWithoutSpaces>[.<COUNTRY>].symbols.<appId>`. A test app declaring
  Library Assert, Test Runner and Any gets exactly those. Nothing is staged that no app
  asked for.
- **The AL compiler and analyzers** - `Microsoft.Dynamics.BusinessCentral.Development.Tools`
  on nuget.org, which carries `alc`, `altool` and CodeCop, AppSourceCop,
  PerTenantExtensionCop and UICop.

- **Non-Microsoft dependencies** (AppSource apps, for instance) - `app.json` dependencies
  with any other publisher are resolved by app ID against `trustedNuGetFeeds` and, unless
  `trustMicrosoftNuGetFeeds` is set to `false`, Microsoft's public `AppSourceSymbols` feed -
  the same feeds and the same default that a Windows-container build resolves them from, so
  nothing extra needs configuring here. Project dependencies within the same repo still come
  from `appDependencyProbingPaths` and the project's own build output, unaffected by any of
  this.

The GitHub Actions cache for Business Central artifacts is switched off for these
builds, since there is no artifact to cache. That frees roughly 1 GB of the
repository's 10 GB cache budget per version and country you build against.

## Which compiler version you get

`vsixFile` keeps its meaning:

| vsixFile | compiler |
|---|---|
| `default` (or unset) | the AL version matching your Business Central version |
| `latest` | the newest released compiler |
| `preview` | the newest prerelease |

The matching AL major is the Business Central major minus 11 - BC 27 uses AL 16, BC 28
uses AL 17, BC 29 uses AL 18. A Business Central major still in preview often has no
released compiler at all; `default` then falls back to that major's newest prerelease
and says so in the log.

A `vsixFile` pointing at a download URL has no NuGet equivalent, so it is rejected.

## When you cannot use it

**Apps targeting `OnPrem` or `Internal`.** Those may use .NET interop, and the NuGet
feeds carry no service tier assemblies, so there is nothing to put on
`assemblyprobingpaths`. The build fails up front with a message naming the app rather
than producing a confusing `AL0451` later.

Apps targeting `Cloud` are never affected - the compiler rejects .NET interop for them
outright (`AL0296: The application object or method 'DotNet' has scope 'OnPrem' and cannot be used for 'Cloud' development`), so they cannot need those assemblies.

**Without `workspaceCompilation`.** `symbolsSource` is honored by the CompileApps
action, which only runs when workspace compilation is enabled. AL-Go warns and falls
back to `artifact` otherwise.

## What this does not change

Everything after the compiler folder is untouched: the same `altool workspace compile`
invocation, the same analyzers, ruleset, preprocessor symbols and features, the same
build output and `failOn` handling, the same incremental-build behavior, the same
artifacts. Publishing and testing still need a container or an online environment - this
only changes where the compiler and symbols come from.

## Falling back

Remove the setting, or set it to `artifact`. Nothing else about the project changes.
