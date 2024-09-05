function RunIncrementVersionNumber {
    Param(
        [string] $projects,
        [string] $versionNumber,
        [switch] $directCommit,
        [switch] $useGhTokenWorkflow,
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'Increment Version Number'
    $parameters = @{
        "projects" = $projects
        "versionNumber" = $versionNumber
        "directCommit" = @("true","false")[!$directCommit]
        "useGhTokenWorkflow" = @("true","false")[!$useGhTokenWorkflow]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}
