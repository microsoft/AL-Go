# Reference Documentation

A vital part of your development processes is reference documentation. AL-Go for GitHub supports the ALDoc tool for reference documentation generation, either continuously as part of CI/CD, manually or scheduled.

> [!NOTE]
> The [ALDoc tool](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/help/help-aldoc-generate-help) generates content based on the source code. Generating content based on source code has many advantages such as accuracy, 100% reflection of the current codebase, less error prone documentation, and it saves time. The ALDoc tool generates documentation from symbolic and syntactical information, code comments, and overall application structure based on input .app file(s). The tool also generates a help site with these reference articles, sorted by the application structure, based on the provided template.

AL-Go for GitHub supports deploying the reference documentation to GitHub Pages. GitHub Pages is websites for you and your projects, hosted directly from your GitHub repository. It is also possible to deploy the reference documentation to other static HTML hosting providers, but this requires some scripting and is not included here.

## GitHub Pages

> [!NOTE}
> GitHub Pages is available in public repositories with GitHub Free and GitHub Free for organizations, and in public and private repositories with GitHub Pro, GitHub Team, GitHub Enterprise Cloud, and GitHub Enterprise Server. For more information, see [GitHub’s plans](https://docs.github.com/en/get-started/learning-about-github/githubs-plans).

Navigate to your Common repository, go to **Settings** -> **Pages** and under **Build and deployment** select **GitHub Actions** as the source.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/c6dad393-bdb2-4106-9a04-6651347a6005) |
|-|

Choose Actions, select the **Deploy Reference Documentation** workflow and click **Run workflow**

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/43535bdd-4f3d-42f2-88cc-db9c501e48c9) |
|-|

When the workflow is done, click the workflow to open workflow details and you will find a URL to your reference documentation in the deploy step. There is also an artifact called github-pages, which is the artifact deployed to the GitHub pages website. This artifact can be deployed to any other hosting provider if needed.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/238e568c-02c9-4c3b-815b-d25b7b30b470) |
|-|

Clicking the link to your reference documentation reveals the website

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/b59f5b08-f30f-41ba-a845-571267da741a) |
|-|

Now, there isn't much documentation in the Common repository as the apps doesn't contain any objects, so let's repeat the above steps with Repo1 (single-project) and MySolution (multi-project) repository.

In all repositories, click the settings icon in the About section to open repository details, specify a description and check **Use your GitHub Pages website**

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/d592e77f-a158-4a24-8856-d93c1e69907a) |
|-|

After this, the link to the reference documentation is available in the upper right corner of your repository landing page.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/d39b95a8-c73c-4c7e-8008-7b4f65655e37) |
|-|

Clicking the link on the multi-project repository, in which we did a release earlier, shows that AL-Go for GitHub includes reference documentation for prior releases as well as the current main repository.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/021e7b5d-139b-40bb-8e4c-a93379c60718) |
|-|

You will see the three projects as "folders" and the apps, which are built in these projects, are listed below. You will also find a **Releases** folder under which earlier versions of the apps from the repository are listed.

## Deploying the reference documentation daily

To allow daily generation of the reference documentation, modify the .github/AL-Go-Settings.json and add a setting like this:

```json
  "DeployReferenceDocumentationSchedule": "0 4 * * *"
```

> [!NOTE]
> This will update the reference documentation every night at 4

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/5b3a1c0a-6696-483c-857a-590e39dfa860) |
|-|

## Deploying the reference documentation continuously

If you want to setup continuous deployment of the reference documentation, you can add this setting:

```json
  "ALDoc": {
    "ContinuousDeployment": true
  }
```

Adding this to the ALGOORGSETTINGS organizational variable causes all repositories to continuously deploy reference documentation:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/898a58ab-f560-4507-9924-c34985d608cb) |
|-|

But you can also add the setting to a repository settings variable called **ALGOREPOSETTINGS** or to the repository settings file **.github/AL-Go-Settings.json** if you only want to enable this for a single repository.

Running CI/CD after enabling continuous deployment reveals the **Deploy Reference Documentation** job being run and the link to the reference documentation is available in the job.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/8a89e9b8-95db-4747-8136-fda4fa78350a) |
|-|

Maybe it is about time to actually explain how you create a development environment and code your app?

---
[Index](Index.md)&nbsp;&nbsp;[next](DevelopmentEnvironments.md)
