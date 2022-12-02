## Feature work checklist

1. Assign the feature to yourself and move it to "In progress" column in https://aka.ms/algoroadmap
1. Update sprint, estimated size and release wave if necessary
1. Make sure the feature is converted to an issue
1. Update the feature documentation with the design details of the feature
1. Perform your work in a private fork (see [scenarios/Contribute.md](scenarios/Contribute.md))
1. Make sure that the issue is updated with implementation details
1. If there are areas left out, enhancements which needs to be completed later, create a new item in backlog and add a reference to this feature
1. Create a Pull Request against https://github.com/microsoft/AL-Go

## Code review checklist

1. Issues fixed by the checkin must be included in .github\RELEASENOTES.md
1. Change to CheckForUpdates action interface must be performed with care (might block existing preview partners from upgrading)
