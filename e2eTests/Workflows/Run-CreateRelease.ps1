function Run-CreateRelease {
    Param(
        [string] $appVersion,
        [string] $name,
        [string] $tag,
        [switch] $draft,
        [switch] $prerelease,
        [switch] $wait,
        [string] $branch = "main"
    )

    $workflowName = 'Create release'
    $parameters = @{
        "appVersion" = $appVersion
        "name" = $name
        "tag" = $tag
        "draft" = @("Y","N")[!$draft]
        "prerelease" = @("Y","N")[!$prerelease]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch
}