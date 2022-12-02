## Release Checklist (release to Preview)

1. Ensure .github\RELEASENOTES.md are up-to-date
    - Include all issues from https://aka.ms/algoroadmap "In Preview" column
    - Top section must be ## Preview
1. Run End 2 End tests
1. Run Deploy workflow
    - Branch to deploy to = Preview
    - Additionally deploy to main = N

## Release Checklist (Release v2.1 - replace with version number)

1. Ensure .github\RELEASENOTES.md are up-to-date
    - Include all issues from https://aka.ms/algoroadmap preview column
1. Change top section in .github\RELEASENOTES.md from ## Preview to ## v2.1
    - Will eventually build this into the deploy command
1. Run End 2 End tests
1. Create release (Code -> Releases -> Draft New Release)
    - Create new tag = v2.1
    - Release title = v2.1
    - Copy/Paste Release Notes section (## v2.1)
    - Set as the latest release -> Publish
1. Run Deploy workflow
    - Branch to deploy to = v2.1
    - Additionally deploy to main = Y
1. Move all In-Preview items in https://aka.ms/algoroadmap to column v2.1
    - Mark as shipped
    - Create column if not existing
    - Close issues, mark as shipped
1. Change top-section of .github\RELEASENOTES.md to ## Preview
    - Will eventually not be needed when deploy command is updated
 
