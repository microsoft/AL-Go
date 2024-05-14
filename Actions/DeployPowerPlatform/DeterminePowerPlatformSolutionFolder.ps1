Param(
    [string] $artifactsFolder,
    [string] $solutionFolder
)

if ($artifactsFolder -ne '') {
  $artifactsFiles = Get-ChildItem -Path (Join-Path $ENV:GITHUB_WORKSPACE $artifactsFolder) -Recurse -File | Select-Object -ExpandProperty FullName
  foreach($filePath in $artifactsFiles){
      ## Find file containing Power Platform keyword
      if($filePath.contains("-PowerPlatformSolution-")){
          Write-Host "Power Platform solution file:"$filePath
          Add-Content -encoding utf8 -path $env:GITHUB_ENV -value "powerPlatformSolutionFilePath=$filePath"
          Add-Content -encoding utf8 -path $env:GITHUB_ENV -value "powerPlatformSolutionFolder=.artifacts/_tempPPSolution/source"
          return
      }
  }
  throw "Not able to find Power Platform solution file in $artifactFolder that contains the artifact keyword '-PowerPlatformSolution-'"
}
elseif ($solutionFolder -ne '') {
  Add-Content -encoding utf8 -path $env:GITHUB_ENV -value "powerPlatformSolutionFolder=$solutionFolder"
}
else {
  throw "No artifactsFolder or solutionFolder specified"
}
