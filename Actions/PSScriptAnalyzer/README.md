# Read Power Platform Settings

Description

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Name1 | Desc1 |
| Name2 | Desc2 |

### Parameters

| Name | Required | Description | .\ |
| :-- | :-: | :-- | :-- |
| path | Yes  | Specifies the path to the scripts or module to be analyzed. Wildcard characters are supported. | powershell |
| excludeRule | No | Omits the specified rules from the Script Analyzer test. Wildcard characters are supported. | |
| recurse | No | Runs Script Analyzer on the files in the Path directory and all subdirectories recursively. | |
| output | Yes | Specifies where the path for the sarif file | results.sarif |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| name | desc |
