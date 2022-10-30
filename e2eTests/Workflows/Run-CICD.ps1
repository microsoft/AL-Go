function Run-CICD {
    Param(
        [switch] $wait,
        [string] $branch = "main"
    )

    $workflowName = 'CI/CD'
    $parameters = @{
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch
}