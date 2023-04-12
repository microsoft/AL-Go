# Versioning
Understanding how AL-Go for GitHub is doing versioning is important for your day to day use of AL-Go for GitHub.

As we saw earlier, the **artifacts** from the first successful build in my repository was called version **1.0.2.1**. Downloading the artifact and unpacking reveals the app inside

| ![image](https://user-images.githubusercontent.com/10775043/231452819-18130b7d-e52d-45ef-9f36-06682a8a1d94.png) |
|-|

Which has the same version number, but why?

As you know, the build number consists of 4 tuples: **major.minor.build.revision**.
- The version number of the build artifact is 100% controlled by AL-Go for GitHub. The **major.minor** are taken from a setting called **RepoVersion** and the **build.revision** part is auto-calculated by AL-Go for GitHub.
- The version number of the app (inside the build artifact) is controlled by **app.json** and **AL-Go for GitHub**. The **major.minor** part is taken from **app.json** and the **build.revision** part is auto-calculated by AL-Go for GitHub.
- The **build** tuple is (by default) the GITHUB_RUN_NUMBER, which is a unique number for each time the CI/CD workflow is run, starting with 1.
- The **revision** typle is (by default) the GITHUB_RUN_ATTEMPT, which is the number of attempts, starting with 0. In my example above, I did re-run the CI/CD workflow once to end up with .1.



