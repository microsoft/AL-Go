# Prerequisites
In order to complete this workshop, you will need a few things. Nothing big, and the workshop builds solely on free functionality of GitHub, because it is using public repositories. In order to use private repositories, you will need a paid SKU for your GitHub organization (Teams should suffice).

You will need:
1. A GitHub account
   - Free should be enough to follow the workshop
1. A GitHub organizational account
   - Free should be enough to follow the workshop
1. An organizational secret called GHTOKENWORKFLOW
   - Containing a personal access token with permissions to modify workflows.
   - The secret should be available to all public repositories (you cannot have organizational secret accessible for private repos in Free GitHub)
1. An organizational variable called ALGOORGSETTINGS
   - Containing the following JSON structure (for performance reasons)
```
    {
        "useCompilerFolder": true,
        "doNotPublishApps": true,
        "artifact": "https://bcartifacts.azureedge.net/sandbox/22.0.54157.55210/us"
    }
```

The combination of useCompilerFolder and doNotPublishApps, means that AL-Go will never actually create a container, which saves a great amount of time.

Later in the workshop, when we want to run tests, we will need to create a container and we will change the settings for that purpose.

**Note** that we are working on making this piece much faster and utilize different ways to run tests in containers, ACIs, VMs or other environments.

With this... - let's get started!

---
[index](Index.md)&nbsp;&nbsp;[next](GetStarted.md)
