# Deprecated features in AL-Go for GitHub

This file contains a list of deprecations in AL-Go for GitHub, sorted by the date after which the support will be removed.

## Old AL-Go versions might stop working any time

Microsoft recommends that you always run the latest version of AL-Go for GitHub.

Old versions of AL-Go for GitHub uses old and unsupported versions of GitHub actions, which might be removed or no longer work due to unresolved dependencies no longer being installed on the GitHub runners.

When handling support requests, we will request that you to use the latest version of AL-Go for GitHub and in general, fixes will only be made available in a preview version of AL-Go for GitHub and subsequently in the next version released.

## Changes in effect after April 1st 2025

<a id="alwaysBuildAllProjects"></a>

### Setting `alwaysBuildAllProjects` will no longer be supported

The old setting would determine whether or not to build all project during the Pull Request workflow. With incremental Builds now supported, please set the `onPull_Request` property of the `incrementalBuilds` setting to false to force full builds in Pull Requests.
```
"incrementalBuilds": {
    "onPull_Request": false
}
```

<a id="_workflow_Schedule"></a>

### Setting `<workflow>Schedule` will no longer be supported

The old setting, where the setting key was a combination of the workflow name and `Schedule` (dynamic setting key) is no longer supported. Instead you need to use a setting called [workflowSchedule](https://aka.ms/algosettings#workflowSchedule) and either use [Conditional Settings](https://aka.ms/algosettings#conditional-settings) or place the setting in a workflow specific settings file. Example using conditional settings:

```
"conditionalSettings": [
    {
        "workflows": [ "Update AL-Go System Files" ],
        "settings": {
            "workflowSchedule": "30 0 * * 0"
        }
    }
]
```

> [!NOTE]
> workflowSchedule is a string and needs to hold a valid crontab (see [crontab guru](https://crontab.guru/) for assistance on creating one)


<a id="cleanModePreprocessorSymbols"></a>

### Setting `cleanModePreprocessorSymbols` will no longer be supported

[preprocessorSymbols](https://aka.ms/algosettings#preprocessorSymbols) are now supported as a global setting and can be applied to buildModes using [Conditional Settings](https://aka.ms/algosettings#conditional-settings). Example:

```
"conditionalSettings": [
    {
        "buildModes": [ "Clean" ],
        "settings": {
            "preprocessorSymbols": [ "CLEAN21", "CLEAN22" ]
        }
    }
]
```
