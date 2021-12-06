# Introducing a dependency to an app on GitBub 

If your app has a dependency to another application on a different GitHub repository, the foreign repository can be added to the dependency probing paths (appDependencyProbingPaths) in the AL-Go settings file. The dependency also must be added to the app.json file as a dependency. During a build all the apps mentioned in the probing paths will be downloaded and installed on the tenant.

appDependencyProbingPaths key in the settings expects a json array with the following structure

"appDependencyProbingPaths" = @(

`    `"[

`        `{ 

`            `""repo"": ""https://github.com/<Owner>/<repository name>"",

`            `""version"": ""<latest, specific version>"",

`            `""release\_status"": ""<release, prerelease, draft>"", 

`            `""authTokenSecret"": ""<Secret Name>"",

`            `""projects"" = ""\*"" 

`        `}

`    `]"

` `)

**“repo”** specifies the url of the foreign repository 

**“version”** specifies the version of the dependency to be downloaded it could be set to **latest** or a specific version.

**“release\_status”** specifies the type of release on the foreign repository. The artifacts can be downloaded from a release, prerelease or a draft.

**“authTokenSecret”** If the foreign repository is private, to download the artifacts an access token is needed. In this case a secret should be added to GitHub secrets or Azure Key vault and the name of the secret should be provided in the settings.

**“projects”** specifies the project in a multi project repo**. “\*”** means all projects.

---
[back](/README.md)
