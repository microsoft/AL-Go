function RunUpdateAlGoSystemFiles {
    Param(
        [string] $templateUrl,
        [switch] $directCommit,
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main",
        [string] $ghTokenWorkflow
    )

    if ($ghTokenWorkflow) {
        SetRepositorySecret -repository $repository -name 'GHTOKENWORKFLOW' -value $ghTokenWorkflow
    }
    $workflowName = 'Update AL-Go System Files'
    $parameters = @{
        "templateUrl" = $templateUrl.Split('|')[0]
        "directCommit" = @("Y","N")[!$directCommit]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}
