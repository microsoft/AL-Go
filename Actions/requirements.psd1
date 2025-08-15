@{
    RootModule = ''
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000000'
    Author = 'YourName'
    Description = 'AL-Go'
    RequiredModules = @(
        @{ ModuleName = 'Az.KeyVault'; ModuleVersion = '5.2.0' },
        @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.15.1' },
        @{ ModuleName = 'Az.Storage'; ModuleVersion = '6.1.1' },
        @{ ModuleName = 'Microsoft.ApplicationInsights'; ModuleVersion = '2.20.0' },
        @{ ModuleName = 'sign'; ModuleVersion = '0.9.1-beta.25278.1' }
    )
}
