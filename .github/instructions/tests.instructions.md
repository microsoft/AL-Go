---
applyTo: 'Tests/**'
---

# AL-Go Testing Instructions

## Overview
This document provides guidelines for writing and maintaining tests in the AL-Go repository using the Pester testing framework.

## Test Framework
- **Framework**: Pester (PowerShell testing framework)
- **Version**: 5.x
- **Test Discovery**: Tests are discovered by `It` blocks within `Describe` blocks

## Test File Structure

### Naming Conventions
- Test files should end with `.Test.ps1`
- Test file names should match the component being tested (e.g., `CheckForUpdates.Action.Test.ps1` for `CheckForUpdates.ps1`)

### Standard Structure
```powershell
Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "Component Name" {
    BeforeAll {
        # Setup code that runs once before all tests
    }

    BeforeEach {
        # Setup code that runs before each test
    }

    AfterEach {
        # Cleanup code that runs after each test
    }

    AfterAll {
        # Cleanup code that runs once after all tests
    }

    It 'Test description' {
        # Test implementation
    }
}
```

## Test Helper Modules

### TestActionsHelper.psm1
- Provides common helper functions for testing
- Imports `DebugLogHelper.psm1` globally, making `OutputWarning`, `OutputError`, etc. available for mocking
- Contains functions like `GetActionScript` for loading action scripts
- Provides `GetTemporaryPath()` function for creating temporary file paths (use this instead of `$PSScriptRoot`)

## Writing Tests

### Test Naming
- Use descriptive test names that explain what is being tested
- Start with the function/component name being tested
- Use present tense (e.g., "handles", "applies", "validates")
- Examples:
  - `'ApplyWorkflowDefaultInputs applies default values to workflow inputs'`
  - `'ApplyWorkflowDefaultInputs handles empty workflowDefaultInputs array'`
  - `'ApplyWorkflowDefaultInputs validates boolean type mismatch'`

### Assertions
Use Pester's `Should` assertions:
```powershell
$result | Should -Be $expected
$result | Should -Not -BeNullOrEmpty
$result | Should -Match "pattern"
{ SomeFunction } | Should -Throw "*error message*"
{ SomeFunction } | Should -Not -Throw
```

### Mocking Functions

#### Mocking Output Functions
```powershell
# Mock OutputWarning to verify no warnings
Mock OutputWarning { }
# ... run function ...
Assert-MockCalled OutputWarning -Times 0

# Mock OutputWarning to verify specific warning
Mock OutputWarning { }
# ... run function ...
Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter {
    $message -like "*expected warning text*"
}

# Mock OutputError with counter
$script:errorCount = 0
Mock OutputError { Param([string] $message) Write-Host "ERROR: $message"; $script:errorCount++ }
# ... run function ...
$script:errorCount | Should -Be 2
```

#### Mock Scope
- Mocks are scoped to the `Describe`, `Context`, or `It` block where they're defined
- `OutputWarning`, `OutputError`, `OutputDebug` are available globally when `TestActionsHelper.psm1` is imported

### Testing Error Conditions
```powershell
It 'Function throws on invalid input' {
    # Use script block with Should -Throw
    { FunctionName -InvalidParam } | Should -Throw "*error message*"
}

It 'Function handles error gracefully' {
    # Verify function doesn't throw
    { FunctionName -Input $value } | Should -Not -Throw
    # Verify error handling occurred
    Assert-MockCalled OutputError -Exactly 1
}
```

## Test Organization

### Group Related Tests
Use `Describe` blocks to group related tests:
```powershell
Describe "CheckForUpdates Action: CheckForUpdates.HelperFunctions.ps1" {
    # Tests for helper functions
}

Describe "YamlClass Tests" {
    # Tests for YAML class
}
```

### Use Context for Sub-grouping
Use `Context` blocks to group related tests within a `Describe` block:
```powershell
Describe "Component" {
    Context "Feature A" {
        It 'behaves this way' { }
        It 'handles edge case' { }
    }

    Context "Feature B" {
        It 'behaves that way' { }
    }
}
```

Example from CheckForUpdates tests:
```powershell
Describe "CheckForUpdates Action: CheckForUpdates.HelperFunctions.ps1" {
    Context "ApplyWorkflowDefaultInputs" {
        It 'applies default values to workflow inputs' { }
        It 'validates boolean type mismatch' { }
    }

    Context "ApplyWorkflowDefaultInputs - Hide Feature" {
        It 'hides boolean inputs when hide is true' { }
        It 'replaces hidden input references in if conditions' { }
    }
}
```

## Edge Cases and Coverage

### Important Edge Cases to Test
1. **Empty/Null inputs**: Test with empty strings, null values, empty arrays
2. **Non-existent resources**: Test with files/settings that don't exist
3. **Type mismatches**: Test with wrong data types
4. **Case sensitivity**: Test with different casing where applicable
5. **Special characters**: Test with YAML special characters, regex patterns
6. **Boundary conditions**: Test minimum/maximum values, empty collections

### Example Edge Case Tests
```powershell
It 'handles empty input array' {
    $result = FunctionName -Input @()
    $result | Should -Not -Throw
}

It 'silently skips non-existent items' {
    Mock OutputWarning { }
    FunctionName -Items @("existing", "non-existent")
    Assert-MockCalled OutputWarning -Times 0
}
```

## Cleanup and Resource Management

### File Cleanup
```powershell
AfterEach {
    if (Test-Path $tempFile) {
        Remove-Item -Path $tempFile -Force
    }
}
```

### Use Temporary Files
Use `GetTemporaryPath()` function instead of `$PSScriptRoot` for temporary files:
```powershell
BeforeAll {
    $tmpFile = Join-Path (GetTemporaryPath) "tempFile.json"
}

AfterEach {
    if (Test-Path $tmpFile) {
        Remove-Item -Path $tmpFile -Force
    }
}
```

## Running Tests

### Run All Tests
```powershell
Invoke-Pester -Path "Tests/"
```

### Run Specific Test File
```powershell
Invoke-Pester -Path "Tests/CheckForUpdates.Action.Test.ps1"
```

### Run Specific Test
```powershell
Invoke-Pester -Path "Tests/CheckForUpdates.Action.Test.ps1" -FullNameFilter "*test name pattern*"
```

### Run with Detailed Output
Use `-Output Detailed` to see individual test results and Context grouping:
```powershell
Invoke-Pester -Path "Tests/CheckForUpdates.Action.Test.ps1" -Output Detailed
```

## Best Practices

1. **Test One Thing**: Each test should verify one specific behavior
2. **Descriptive Names**: Test names should clearly describe what's being tested
3. **Arrange-Act-Assert**: Structure tests with clear setup, execution, and verification
4. **Mock External Dependencies**: Mock file I/O, API calls, external commands
5. **Verify No Side Effects**: Test that functions don't produce warnings/errors when they shouldn't
6. **Clean Up**: Always clean up temporary files and resources
7. **Independent Tests**: Tests should not depend on each other's execution order
8. **Use BeforeAll for Expensive Setup**: Import modules and load data once per Describe block
9. **Test Error Paths**: Don't just test the happy path - test error handling too
10. **Keep Tests Fast**: Mock expensive operations, use minimal test data

## Common Patterns

### Testing Functions That Modify Objects
```powershell
It 'modifies object correctly' {
    $obj = CreateTestObject
    ModifyObject -Object $obj
    $obj.Property | Should -Be $expectedValue
}
```

### Testing with Settings Objects
```powershell
$repoSettings = @{
    "settingName" = @(
        @{ "name" = "value1" },
        @{ "name" = "value2" }
    )
}
FunctionName -Settings $repoSettings
```

### Testing Regex Patterns
```powershell
It 'replaces pattern correctly' {
    $result = ReplacePattern -Input $testString -Pattern "regex"
    $result | Should -Match "expected"
    $result | Should -Not -Match "unexpected"
}
```

## Debugging Tests

### View Test Output
```powershell
# Use Write-Host in tests to see output
It 'test name' {
    Write-Host "Debug: $variable"
    # assertions
}
```

### Run Single Test for Debugging
```powershell
# Exact match (no wildcards needed)
Invoke-Pester -Path "file.Test.ps1" -FullNameFilter "exact test name"

# Partial match (with wildcards)
Invoke-Pester -Path "file.Test.ps1" -FullNameFilter "*pattern*"
```

### Check Mock Calls
```powershell
Mock SomeFunction { } -Verifiable
# ... run code ...
Assert-MockCalled SomeFunction -Times 1 -ParameterFilter { $param -eq "value" }
```
