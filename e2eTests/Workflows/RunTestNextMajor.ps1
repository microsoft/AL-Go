function RunTestNextMajor {
    Param(
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main",
        [string] $insiderSasToken
    )

    if ($insiderSasToken) {
        SetRepositorySecret -repository $repository -name 'INSIDERSASTOKEN' -value $insiderSasToken
    }
    $workflowName = 'Test Next Major'
    $parameters = @{
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}