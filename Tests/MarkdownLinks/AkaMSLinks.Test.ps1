Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

Describe "Aka.ms links in ReleaseNotes.md should be full links" {
    It 'Check aka.ms links begin with https://' {
        $releaseNotes = Join-Path (GetRepoRoot) RELEASENOTES.md

        $releaseNotesContent = Get-Content -Path $releaseNotes -Encoding UTF8 -Raw
        $akaMSLinks = Select-String -InputObject $releaseNotesContent -Pattern 'aka.ms/' -AllMatches
        foreach ($match in $akaMSLinks.Matches) {
            # Check that aka.ms starts with https://
            $releaseNotesContent.Substring($match.Index - 8, 8) | Should -Be 'https://'
        }
    }
}