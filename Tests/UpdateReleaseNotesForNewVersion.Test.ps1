$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe 'UpdateReleaseNotesForNewVersion Tests' {
    BeforeAll {
        # Dot-source the script to make its functions available without running the main git logic
        . (Join-Path $PSScriptRoot "..\Internal\Scripts\UpdateReleaseNotesForNewVersion.ps1" -Resolve)
    }

    It 'Prepends a new version header to the release notes' {
        $releaseNotes = "### Some new feature`n`nDescription of the feature."
        $result = Add-VersionToReleaseNotes -releaseNotes $releaseNotes -version 'v9.0'
        $result | Should -Be "## v9.0`n`n### Some new feature`n`nDescription of the feature."
    }

    It 'Is idempotent when the top-most version header already matches' {
        $releaseNotes = "## v9.0`n`n### Some existing feature`n`nDescription."
        $result = Add-VersionToReleaseNotes -releaseNotes $releaseNotes -version 'v9.0'
        $result | Should -Be $releaseNotes
    }

    It 'Seals unreleased notes above an existing older version header' {
        $releaseNotes = "### New feature`n`nDescription.`n`n## v8.3`n`nOld notes."
        $result = Add-VersionToReleaseNotes -releaseNotes $releaseNotes -version 'v9.0'
        $result | Should -Be "## v9.0`n`n### New feature`n`nDescription.`n`n## v8.3`n`nOld notes."
    }

    It 'Normalizes CRLF line endings to LF' {
        $releaseNotes = "### New feature`r`n`r`nDescription."
        $result = Add-VersionToReleaseNotes -releaseNotes $releaseNotes -version 'v9.0'
        $result | Should -Be "## v9.0`n`n### New feature`n`nDescription."
    }

    It 'Handles empty release notes' {
        $result = Add-VersionToReleaseNotes -releaseNotes '' -version 'v9.0'
        $result | Should -Be "## v9.0`n`n"
    }
}
