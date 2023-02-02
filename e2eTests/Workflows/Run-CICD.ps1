function Run-CICD {
    Param(
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'Official Build'
    $parameters = @{
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}