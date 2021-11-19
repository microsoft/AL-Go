function Run-IncrementVersionNumber {
    Param(
        [string] $versionNumber,
        [switch] $directCommit,
        [switch] $wait,
        [string] $branch = "main"
    )

    $workflowName = 'Increment Version Number'
    $parameters = @{
        "versionNumber" = $versionNumber
        "directCommit" = @("Y","N")[!$directCommit]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch
}