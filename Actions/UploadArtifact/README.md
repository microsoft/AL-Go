# Upload Artifact

Uploads a build artifact with automatic retry on transient failures.

This action wraps `actions/upload-artifact` with retry logic to mitigate transient GitHub Actions infrastructure issues that can cause silent upload failures. If the first upload attempt fails, the action waits 15 seconds and retries once.

## INPUT

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| name | Yes | Artifact name | |
| path | Yes | Path to the file or directory to upload | |
| if-no-files-found | | Action to take if no files are found (warn, error, ignore) | warn |
| retention-days | | Number of days to retain the artifact. 0 means use the repository default | 0 |
