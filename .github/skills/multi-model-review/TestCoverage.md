# Test Coverage Checklist

When reviewing AL-Go code changes, check for adequate test coverage:

## What Needs Tests

- New public functions need corresponding Pester tests in `Tests/`
- New settings need tests verifying default values and behavior
- New logic branches (if/else, switch cases) need tests covering each path
- Bug fixes should include a regression test

## Test Quality

- Tests must import/dot-source the actual source — never reimplement logic in the test
- Each `It` block should have at least one meaningful `Should` assertion
- Use specific assertions (`Should -Be`, `Should -BeExactly`, `Should -Throw`) over generic ones
- Use `Mock` for external dependencies; verify with `Should -Invoke` including `-Times` and `-ParameterFilter`
- Do not mock the function under test — only its dependencies

## Culture & Locale

- When testing DateTime parsing or string formatting, test across multiple cultures:
  `@('en-US', 'de-DE', 'ja-JP')`
- This catches bugs that only appear on non-en-US runners

## Edge Cases

- Test empty inputs, null values, and boundary conditions
- For string manipulation, verify behavior with unexpected input
- For version parsing, test both 2-segment and 3-segment formats

## E2E Tests

- E2E tests must clean up test repositories after completion (use `try`/`finally`)
- Use polling loops with previous run ID tracking, not fixed `Start-Sleep` durations
