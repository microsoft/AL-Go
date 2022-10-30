function Run-TestNextMajor {
    Param(
        [switch] $wait,
        [string] $branch = "main"
    )

    $workflowName = 'Test Next Major'
    $parameters = @{
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch
}