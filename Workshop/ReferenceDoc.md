# Reference Documentation

A vital part of your development processes is reference documentation. AL-Go for GitHub supports the ALDoc tool for reference documentation generation, either continuously as part of CI/CD, manually or scheduled.

> [!NOTE]
> The [ALDoc tool](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/help/help-aldoc-generate-help) generates content based on the source code. Generating content based on source code has many advantages such as accuracy, 100% reflection of the current codebase, less error-prone documentation, and it saves time. The ALDoc tool generates documentation from symbolic and syntactical information, code comments, and overall application structure based on input .app file(s). The tool also generates a help site with these reference articles, sorted by the application structure, based on the provided template.

AL-Go for GitHub supports deploying the reference documentation to GitHub Pages. GitHub Pages is websites for you and your projects, hosted directly from your GitHub repository. It is also possible to deploy the reference documentation to other static HTML hosting providers, but this requires some scripting and is not included here.

## GitHub Pages

> [!NOTE]
> GitHub Pages is available in public repositories with GitHub Free and GitHub Free for organizations, and in public and private repositories with GitHub Pro, GitHub Team, GitHub Enterprise Cloud, and GitHub Enterprise Server. For more information, see [GitHub’s plans](https://docs.github.com/en/get-started/learning-about-github/githubs-plans).

Navigate to your Common repository, go to **Settings** -> **Pages** and under **Build and deployment** select **GitHub Actions** as the source.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/a71fc75f-027c-4ef9-a8f4-63b1332ac9a4) |
|-|

Choose Actions, select the **Deploy Reference Documentation** workflow and click **Run workflow**

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/43b88ca8-0420-48f0-b875-3fab3393bbe7) |
|-|

When the workflow is done, click the workflow to open workflow details and you will find a URL to your reference documentation in the deploy step. There is also an artifact called github-pages, which is the artifact deployed to the GitHub pages website. This artifact can be deployed to any other hosting provider if needed.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/452d1a68-c6f3-4adb-964f-bfa5a2186c5a) |
|-|

Clicking the link to your reference documentation reveals the website

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/52b4f77b-aa52-474b-a2b5-3e25425c2843) |
|-|

Now, there isn't much documentation in the Common repository as the apps doesn't contain any objects, so let's repeat the above steps with Repo1 (single-project) and MySolution (multi-project) repository.

In all repositories, click the settings icon in the About section to open repository details, specify a description and check **Use your GitHub Pages website**

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/53f2223b-d102-4194-9ebe-3d1789255819) |
|-|

After this, the link to the reference documentation is available in the upper right corner of your repository landing page.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/556de268-c8f3-4e55-a282-252ff9b39d70) |
|-|

Clicking the link on the multi-project repository, in which we did a release earlier, shows that AL-Go for GitHub includes reference documentation for prior releases as well as the current main repository.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/00e38e2e-1429-43cc-b16c-445a9303f997) |
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
  "alDoc": {
    "continuousDeployment": true
  }
```

> [!NOTE]
> There are other settings in the ALDoc settings structure, which controls the generation of the reference documentation. Inspect [https://aka.ms/algosettings#aldoc](https://aka.ms/algosettings#aldoc) to see them all.

Adding this to the ALGOORGSETTINGS organizational variable causes all repositories to continuously deploy reference documentation:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/898a58ab-f560-4507-9924-c34985d608cb) |
|-|

But you can also add the setting to a repository settings variable called **ALGOREPOSETTINGS** or to the repository settings file **.github/AL-Go-Settings.json** if you only want to enable this for a single repository.

Running CI/CD after enabling continuous deployment reveals the **Deploy Reference Documentation** job being run and the link to the reference documentation is available in the job.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/a92b4dad-67fe-4c57-81f2-a7fc2abfd848) |
|-|

Maybe it is about time to actually explain how you create a development environment and code your app?

______________________________________________________________________

[Index](Index.md)  [next](DevelopmentEnvironments.md)
