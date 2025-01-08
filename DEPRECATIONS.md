# Deprecated features in AL-Go for GitHub

This file contains a list of deprecations in AL-Go for GitHub, sorted by the date after which the support will be removed.

## Old AL-Go versions might stop working any time

Microsoft recommends that you always run the latest version of AL-Go for GitHub.

Old versions of AL-Go for GitHub uses old and unsupported versions of GitHub actions, which might be removed or no longer work due to unresolved dependencies no longer being installed on the GitHub runners.

When handling support requests, we will request that you to use the latest version of AL-Go for GitHub and in general, fixes will only be made available in a preview version of AL-Go for GitHub and subsequently in the next version released.

## Changes in effect after April 1st 2025

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
