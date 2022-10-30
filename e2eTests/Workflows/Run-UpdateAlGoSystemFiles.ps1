function Run-UpdateAlGoSystemFiles {
    Param(
        [string] $templateUrl,
        [switch] $directCommit,
        [switch] $wait,
        [string] $branch = "main"
    )

    $workflowName = 'Update AL-Go System Files'
    $parameters = @{
        "templateUrl" = $templateUrl
        "directCommit" = @("Y","N")[!$directCommit]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch
}
