function Run-CreateTestApp {
    Param(
        [string] $project,
        [string] $name,
        [string] $publisher,
        [string] $idrange,
        [switch] $directCommit,
        [switch] $wait,
        [string] $branch = "main"
    )

    $workflowName = 'Create a new test app'
    $parameters = @{
        "project" = $project
        "name" = $name
        "publisher" = $publisher
        "idrange" = $idrange
        "directCommit" = @("Y","N")[!$directCommit]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch
}