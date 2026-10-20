# Findings-report role contract fixtures

- `bcquality-findings-report.b74967bc.schema.json`: `schemas/findings-report.schema.json`
  from [microsoft/BCQuality](https://github.com/microsoft/BCQuality) at the pinned ref
  `b74967bc5b7a454eae19d6a1250199afd869f064` (MIT). Its content is identical at
  `130d5de6c4bd72d2158240fe431862b6434c735a`.
- `leaf-*.json`: unmodified leaf reports from BC-Bench workflow run
  [36852068369](https://github.com/microsoft/BC-Bench/actions/runs/36852068369).
  The `leaf-not-applicable-root-fields.*` reports are the three leaves rejected
  for super-skill-only fields (Bug 652544). The `leaf-completed.*` report is a
  valid leaf with a finding.
