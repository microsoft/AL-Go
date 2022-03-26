## Branching strategy ##
A version control like Git gives you flexibility in how you share and manage code. **Your team should find a balance between this flexibility and the need to collaborate and share code.**

Adopt a branching strategy for your team that is flexible and yet easy to adopt by your team. You can collaborate better and spend less time managing version control and more time developing code.

### Keep it simple and relevant ###
Keep your branch strategy simple and relevant to your needs. If your team is small and collaboration is limited, a simpler branching strategy will be a better option. When choosing a branching strategy, pay attention to these three concepts:

- Use feature branches for all new features and bug fixes. 
- Merge feature branches into the main branch using pull requests.
- Keep a high quality, up-to-date main branch. 
    read more here https://docs.microsoft.com/en-us/azure/devops/repos/git/git-branching-guidance?view=azure-devops#keep-a-high-quality-up-to-date-main-branch

### Use a feature branch ###
A CI/CD workflow runs when a pull request is created. In this case the artifacts should NOT be published from a feature branch (ignore the CD part of the workflow).

CI/CD workflow also runs when a pull request is merged to main branch. Use the artifacts generated in this workflow to create a release. CD part can use the artifact generated in CI, for example to deploy them to a sandbox environment.

Read more about use of feature branches and pull requests here https://docs.microsoft.com/en-us/azure/devops/repos/git/git-branching-guidance?view=azure-devops#keep-your-branch-strategy-simple

**Useful links**
Read more about flow and some of the basic terminology here https://docs.microsoft.com/en-us/devops/develop/how-microsoft-develops-devops

Here you can find useful information about branching patterns and anti-patterns https://youtu.be/t_4lLR6F_yk


---
[back](/README.md)

