function Run-PublishToEnvironment {
    Param(
        [string] $appVersion,
        [string] $environmentName,
        [switch] $wait,
        [string] $branch = "main"
    )

    $workflowName = 'Publish To Environment'
    $parameters = @{
        "appVersion" = $appVersion
        "environmentName" = $environmentName
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch
}