# Validate the inputs for the create release workflow
Param(
    [Parameter(Mandatory=$true)]
    [hashtable] $settings,

    [Parameter(Mandatory=$true)]
    [PSCustomObject] $eventPath
)

foreach($inputname in $eventPath.inputs.PSObject.Properties.Name) {
  $inputValue = $eventPath.inputs."$inputName"
  switch ($inputName) {
    'UpdateVersionNumber' {
      # An empty value means that the version number should not be updated
      if ($inputValue) {
        Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue $inputValue
      }
    }
    'ReleaseType' {
      Validate-ReleaseType -inputName $inputName -inputValue $inputValue
    }
  }
}
