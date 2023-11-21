# Prerequisites
In order to complete this workshop, you will need a few things. Nothing big, and the workshop builds solely on free functionality of GitHub, because it is using public repositories. In order to use private repositories, you will need a paid SKU for your GitHub organization (Teams should suffice).

You will need:
1. A GitHub account
   - Free should be enough to follow the workshop
1. A GitHub organizational account
   - Free should be enough to follow the workshop
1. An organizational secret called GHTOKENWORKFLOW containing a personal access token (classic or fine-grained)
   - Using classic tokens, the token should have **workflow** permissions (automatically includes repo permissions)
   - Using Fine-grained tokens, the token should have **Read and Write** access to **Contents**, **Pull Requests** and **Workflows** (automatically includes Read-only access to Metadata)
   - The secret should be available to all public repositories (you cannot have organizational secret accessible for private repos in Free GitHub)
1. An organizational variable called ALGOORGSETTINGS
   - Containing the following JSON structure (for performance reasons)

```json
  {
    "useCompilerFolder": true,
    "doNotPublishApps": true,
    "artifact": "https://bcartifacts.azureedge.net/sandbox/23.0.12034.13450/us"
  }
```

The combination of useCompilerFolder and doNotPublishApps, means that AL-Go will never actually create a container, which saves a great amount of time.

Later in the workshop, when we want to run tests, we will need to create a container and we will change the settings for that purpose.

**Note** that we are working on making this piece much faster and utilize different ways to run tests in containers, ACIs, VMs or other environments.

With this... - let's get started!

---
[index](Index.md)&nbsp;&nbsp;[next](GetStarted.md)
