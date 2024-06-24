function RunCreateOnlineDevelopmentEnvironment {
    Param(
        [string] $environmentName,
        [switch] $reUseExistingEnvironment,
        [switch] $directCommit,
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'Create Online Dev. Environment'
    $parameters = @{
        "environmentName" = $environmentName
        "reUseExistingEnvironment" = @("true","false")[!$reUseExistingEnvironment]
        "directCommit" = @("true","false")[!$directCommit]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}
