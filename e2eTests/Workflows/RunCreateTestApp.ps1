function RunCreateTestApp {
    Param(
        [string] $project,
        [string] $name,
        [string] $publisher,
        [string] $idrange,
        [switch] $directCommit,
        [switch] $useGhTokenWorkflow,
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'Create a new test app'
    $parameters = @{
        "project" = $project
        "name" = $name
        "publisher" = $publisher
        "idrange" = $idrange
        "directCommit" = @("true","false")[!$directCommit]
        "useGhTokenWorkflow" = @("true","false")[!$useGhTokenWorkflow]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}
