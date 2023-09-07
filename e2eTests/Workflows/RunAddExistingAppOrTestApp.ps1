function RunAddExistingAppOrTestApp {
    Param(
        [string] $project,
        [string] $url,
        [switch] $directCommit,
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'Add existing app or test app'
    $parameters = @{
        "project" = $project
        "url" = $url
        "directCommit" = @("Y","N")[!$directCommit]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}