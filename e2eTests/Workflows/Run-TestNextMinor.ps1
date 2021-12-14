function Run-TestNextMinor {
    Param(
        [switch] $wait,
        [string] $branch = "main"
    )

    $workflowName = 'Test Next Minor'
    $parameters = @{
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch
}