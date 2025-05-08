# Validate the inputs for the increment version workflow
Param(
    [Parameter(Mandatory=$true)]
    [hashtable] $settings,

    [Parameter(Mandatory=$true)]
    [PSCustomObject] $eventPath
)

foreach($inputname in $eventPath.inputs.PSObject.Properties.Name) {
  $inputValue = $eventPath.inputs."$inputName"
  switch ($inputName) {
    'VersionNumber' {
      Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue $inputValue
    }
  }
}
