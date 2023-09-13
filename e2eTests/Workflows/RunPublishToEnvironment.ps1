function RunPublishToEnvironment {
    Param(
        [string] $appVersion,
        [string] $environmentName,
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'Publish To Environment'
    $parameters = @{
        "appVersion" = $appVersion
        "environmentName" = $environmentName
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}