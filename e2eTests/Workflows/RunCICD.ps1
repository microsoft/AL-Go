function RunCICD {
    Param(
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'CI/CD'
    $parameters = @{
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}