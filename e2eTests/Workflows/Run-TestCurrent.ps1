function Run-TestCurrent {
    Param(
        [switch] $wait,
        [string] $branch = "main"
    )

    $workflowName = 'Test Current'
    $parameters = @{
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch
}