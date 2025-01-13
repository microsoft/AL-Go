# PowerShell Script Analyzer

Run the PSScriptAnalyzer tool

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| path | Yes | Specifies the path to the scripts or module to be analyzed. Wildcard characters are supported. | powershell |
| excludeRule | No | Comma separated list of PSScriptAnalyzer rules to exclude. Wildcard characters are supported. | |
| recurse | No | Runs Script Analyzer on the files in the Path directory and all subdirectories recursively. | |
| output | Yes | Specifies where the path for the sarif file | results.sarif |

## OUTPUT

### ENV variables

none

### OUTPUT variables

none
