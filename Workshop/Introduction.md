# Introduction

Introduction to GitHub, AL-Go for GitHub, personal and organizational accounts.

## What is GitHub?

GitHub is a code hosting platform for collaboration and version control.

Built for developers, inspired by the way you work.

From open source to business, you can host and review code, manage projects, and build software alongside 83 million developers.

Owned by Microsoft, who is heavily investing in evolving GitHub.

[See more here](https://github.com/)

______________________________________________________________________

## What is AL-Go For GitHub?

The Plug-and-play DevOps solution for Business Central development on GitHub

- Open source and free for all (GitHub costs accrue)
- Supports PTEs and AppSource apps
- Easy to get started, easy to use, easy to maintain
- No prior knowledge in docker, PowerShell or yaml needed
- No need for a DevOps engineer
- DevOps becomes a tool, not an investment area

[See more here](https://github.com/microsoft/AL-Go)

______________________________________________________________________

## Why GitHub?

As of June 2022, GitHub reported having over 83 million developers and more than 200 million repositories, including at least 28 million public repositories.
It is the largest source code host as of November 2021.

Some provocative comparison statements, which are the opinion of the author:

**If Azure DevOps is Enterprise Level DevOps**<br/>    then GitHub is it’s lean and simple DevOps sibling

**If DevOps engineers love Azure DevOps**<br/>    then Developers love GitHub

**If Azure DevOps is like Visual Studio**<br/>    then GitHub is like VS Code

**Other alternatives for Business Central on Azure DevOps exists**<br/>    none existed for GitHub before AL-Go for GitHub

**Yes, Azure DevOps is more feature rich**<br/>    but Microsoft is investing heavily in GitHub…

______________________________________________________________________

## Working with GitHub

### Every user needs a personal GitHub account

- You can have any number of private or public repositories under your personal account.
- This is your work area; this is not where you store production code

### A user can be a member of any number of organizations

- An organization can have any number of private or public repositories
- This is for production code

### A user can have access to any number of repositories

- Making a user a member of a single repository works, but it might come with some problems
- Organize your organizations and repositories wisely.

______________________________________________________________________

## Personal vs. Organizational accounts

| Personal Account | Organizational Account |
|--|--|
| Your identity on GitHub | Enhances collaboration |
| Sandbox for your work | Belongs to a user or an org |
| Unlimited private and public repos | Unlimited private and public repos |
| Most people will use just one | Can have any number of members |
| Free vs. Pro ($4) | Free vs. Team ($4) vs. Enterprise ($21) |
| GitHub Actions execution minutes<br/>- 2000 vs. 3000 min/month | GitHub Actions execution minutes<br />- 2000 vs. 3000 vs. 50.000 min/month |

> [!NOTE]
> Windows OS consumes 2 minutes per minute

[See more here](https://github.com/)

______________________________________________________________________

## When to use organizational accounts

### Owner of organization owns the code

- Can share secrets, GitHub runners, access tokens and more

### ISVs implementing AppSource apps

- Should place these in one or more repositories in one organization
- Likely Teams Account ($4 per user/month)

### VARs implementing Per Tenant Extensions

- Should place those in an organization owned by the customer with the partner as collaborator
- VARs likely will need their own org. with a Teams Account ($4 per user/month)
- Free account is likely sufficient for Customer organization account

Open Source apps can be public - other apps should be private

______________________________________________________________________

## Organizational accounts

### Shared runners

- Runners defined on the organization can be used by all repositories
- Enterprise accounts can create runner groups and assign policies

### Shared secrets (not for free plan)

- Teams or Enterprise accounts can create secrets on the organization and share to repositories

### Shared cost

- Billing goes to organization instead of your personal plan

______________________________________________________________________

[Index](Index.md)  [next](Prerequisites.md)
