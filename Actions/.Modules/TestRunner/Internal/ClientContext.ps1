#requires -Version 5.0
using namespace Microsoft.Dynamics.Framework.UI.Client
using namespace Microsoft.Dynamics.Framework.UI.Client.Interactions

class ClientContext {

    $events = @()
    $clientSession = $null
    $culture = ""
    $caughtForm = $null
    $IgnoreErrors = $true

    ClientContext([string] $serviceUrl, [bool] $disableSSL, [pscredential] $credential, [timespan] $interactionTimeout, [string] $culture) 
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::UserNamePassword), (New-Object System.Net.NetworkCredential -ArgumentList $credential.UserName, $credential.Password), $disableSSL, $interactionTimeout, $culture)
    }

    ClientContext([string] $serviceUrl, [pscredential] $credential, [bool] $disableSSL, [timespan] $interactionTimeout, [string] $culture) 
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::UserNamePassword), (New-Object System.Net.NetworkCredential -ArgumentList $credential.UserName, $credential.Password), $disableSSL, $interactionTimeout, $culture)
    }

    ClientContext([string] $serviceUrl, [pscredential] $credential) 
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::UserNamePassword), (New-Object System.Net.NetworkCredential -ArgumentList $credential.UserName, $credential.Password), $false, ([timespan]::FromHours(12)), 'en-US')
    }

    ClientContext([string] $serviceUrl, [bool] $disableSSL, [timespan] $interactionTimeout, [string] $culture) 
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::Windows), $null, $disableSSL, $interactionTimeout, $culture)
    }

    ClientContext([string] $serviceUrl, [timespan] $interactionTimeout, [string] $culture) 
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::Windows), $null, $false, $interactionTimeout, $culture)
    }
    
    ClientContext([string] $serviceUrl) 
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::Windows), $null, $false, ([timespan]::FromHours(12)), 'en-US')
    }

    ClientContext([string] $serviceUrl, [Microsoft.Dynamics.Framework.UI.Client.tokenCredential] $tokenCredential, [bool] $disableSSL, [timespan] $interactionTimeout = ([timespan]::FromHours(12)), [string] $culture = 'en-US')
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::AzureActiveDirectory), $tokenCredential, $disableSSL, $interactionTimeout, $culture)
    }

    ClientContext([string] $serviceUrl, [Microsoft.Dynamics.Framework.UI.Client.tokenCredential] $tokenCredential, [timespan] $interactionTimeout = ([timespan]::FromHours(12)), [string] $culture = 'en-US')
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::AzureActiveDirectory), $tokenCredential, $false, $interactionTimeout, $culture)
    }
    
    Initialize([string] $serviceUrl, [AuthenticationScheme] $authenticationScheme, [System.Net.ICredentials] $credential, [bool] $disableSSL, [timespan] $interactionTimeout, [string] $culture) {
                  
        $clientServicesUrl = $serviceUrl
        if(-not $clientServicesUrl.Contains("/cs/"))
        {
            if($clientServicesUrl.Contains("?"))
            {
                $clientServicesUrl = $clientServicesUrl.Insert($clientServicesUrl.LastIndexOf("?"),"cs/")
            }
            else
            {
                $clientServicesUrl = $clientServicesUrl.TrimEnd("/")
                $clientServicesUrl = $clientServicesUrl + "/cs/"
            }
        }
        $addressUri = New-Object System.Uri -ArgumentList $clientServicesUrl
        $jsonClient = New-Object JsonHttpClient -ArgumentList $addressUri, $credential, $authenticationScheme
        $httpClient = ($jsonClient.GetType().GetField("httpClient", [Reflection.BindingFlags]::NonPublic -bor [Reflection.BindingFlags]::Instance)).GetValue($jsonClient)
        $httpClient.Timeout = $interactionTimeout

        # On PS7/.NET Core, ServicePointManager.ServerCertificateValidationCallback does not
        # affect HttpClient instances. We must set the callback on the HttpClientHandler directly.
        # The handler is accessed via reflection since JsonHttpClient creates it internally.
        if ($disableSSL -and $global:PSVersionTable.PSVersion.Major -ge 6) {
            $this.DisableSSLOnHttpClient($httpClient)
        }

        $this.clientSession = New-Object ClientSession -ArgumentList $jsonClient, (New-Object NonDispatcher), (New-Object 'TimerFactory[TaskTimer]')
        $this.culture = $culture
        $this.OpenSession()
    }

    DisableSSLOnHttpClient($httpClient) {
        # Walk the handler chain to find all HttpClientHandler instances and disable SSL on each.
        # JsonHttpClient wraps handlers in a DelegatingHandler chain (e.g. BasicAuthHandler for NavUserPassword).
        $handlerField = [System.Net.Http.HttpMessageInvoker].GetField("_handler", [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
        $handler = $handlerField.GetValue($httpClient)
        $this.DisableSSLOnHandler($handler)
    }

    DisableSSLOnHandler($handler) {
        if ($handler -is [System.Net.Http.HttpClientHandler]) {
            $handler.ServerCertificateCustomValidationCallback = [System.Net.Http.HttpClientHandler]::DangerousAcceptAnyServerCertificateValidator
        }
        # Walk DelegatingHandler chain to find nested HttpClientHandlers
        if ($handler -is [System.Net.Http.DelegatingHandler]) {
            $innerHandler = $handler.InnerHandler
            if ($innerHandler) {
                $this.DisableSSLOnHandler($innerHandler)
            }
        }
    }

    OpenSession() {
        $clientSessionParameters = New-Object ClientSessionParameters
        $clientSessionParameters.CultureId = $this.culture
        $clientSessionParameters.UICultureId = $this.culture
        $clientSessionParameters.AdditionalSettings.Add("IncludeControlIdentifier", $true)        
    
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName MessageToShow -Action {
            Write-Host -ForegroundColor Yellow "Message : $($EventArgs.Message)"
        })
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName CommunicationError -Action {
            HandleError -ErrorMessage "CommunicationError : $($EventArgs.Exception.Message)"
        })
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName UnhandledException -Action {
            HandleError -ErrorMessage "UnhandledException : $($EventArgs.Exception.Message)"
        })
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName InvalidCredentialsError -Action {
            HandleError -ErrorMessage "InvalidCredentialsError"
        })
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName UriToShow -Action {
            Write-Host -ForegroundColor Yellow "UriToShow : $($EventArgs.UriToShow)"
        })
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName DialogToShow -Action {
            $form = $EventArgs.DialogToShow
            if ( $form.ControlIdentifier -eq "00000000-0000-0000-0800-0000836bd2d2" ) {
                $errorControl = $form.ContainedControls | Where-Object { $_ -is [ClientStaticStringControl] } | Select-Object -First 1                
                HandleError -ErrorMessage "ERROR: $($errorControl.StringValue)"
            } elseif ( $form.ControlIdentifier -eq "00000000-0000-0000-0300-0000836bd2d2" ) {
                $errorControl = $form.ContainedControls | Where-Object { $_ -is [ClientStaticStringControl] } | Select-Object -First 1                
                Write-Host -ForegroundColor Yellow "WARNING: $($errorControl.StringValue)"
            } elseif ( $form.MappingHint -eq "InfoDialog" ) {
                $errorControl = $form.ContainedControls | Where-Object { $_ -is [ClientStaticStringControl] } | Select-Object -First 1                
                Write-Host -ForegroundColor Yellow "INFO: $($errorControl.StringValue)"
            }
        })
    
        $this.clientSession.OpenSessionAsync($clientSessionParameters)
        $this.AwaitState([ClientSessionState]::Ready)
    }

    SetIgnoreServerErrors([bool] $IgnoreServerErrors) {
        $this.IgnoreErrors = $IgnoreServerErrors
    }

   HandleError([string] $ErrorMessage) {
        Remove-ClientSession
        if ($this.IgnoreErrors) {
            Write-Host -ForegroundColor Red $ErrorMessage
        } else {
            throw $ErrorMessage
        }
   }   

    Dispose() {
        $this.events | % { Unregister-Event $_.Name }
        $this.events = @()
    
        try {
            if ($this.clientSession -and ($this.clientSession.State -ne ([ClientSessionState]::Closed))) {
                $this.clientSession.CloseSessionAsync()
                $this.AwaitState([ClientSessionState]::Closed)
            }
        }
        catch {
        }
    }
    
    AwaitState([ClientSessionState] $state) {
        While ($this.clientSession.State -ne $state) {
            Start-Sleep -Milliseconds 100
            if ($this.clientSession.State -eq [ClientSessionState]::InError) {
                if ($this.clientSession.LastException) {
                    Write-Host -ForegroundColor Red "ClientSession in Error. LastException: $($this.clientSession.LastException.Message)"
                    Write-Host -ForegroundColor Red "StackTrace: $($this.clientSession.LastException.StackTrace)"
                }
                throw "ClientSession in Error"
            }
            if ($this.clientSession.State -eq [ClientSessionState]::TimedOut) {
                throw "ClientSession timed out"
            }
            if ($this.clientSession.State -eq [ClientSessionState]::Uninitialized) {
                throw "ClientSession is Uninitialized"
            }
        }
    }
    
    InvokeInteraction([ClientInteraction] $interaction) {
        $this.clientSession.InvokeInteractionAsync($interaction)
        $this.AwaitState([ClientSessionState]::Ready)
    }
    
    [ClientLogicalForm] InvokeInteractionAndCatchForm([ClientInteraction] $interaction) {
        $Global:PsTestRunnerCaughtForm = $null
        $formToShowEvent = Register-ObjectEvent -InputObject $this.clientSession -EventName FormToShow -Action { 
            $Global:PsTestRunnerCaughtForm = $EventArgs.FormToShow
        }
        try {
            $this.InvokeInteraction($interaction)
            if (!($Global:PsTestRunnerCaughtForm)) {
                $this.CloseAllWarningOrInfoForms()
            }
        }
        catch
        {
            $ErrorMessage = $_.Exception.Message
            $FailedItem = $_.Exception.ItemName
            Write-Host "Error:" $ErrorMessage "Item: " $FailedItem
        }
        finally {
            Unregister-Event -SourceIdentifier $formToShowEvent.Name
        }
        $form = $Global:PsTestRunnerCaughtForm
        Remove-Variable PsTestRunnerCaughtForm -Scope Global
        return $form
    }
    
    [ClientLogicalForm] OpenForm([int] $page) {
        $interaction = New-Object OpenFormInteraction
        $interaction.Page = $page
        return $this.InvokeInteractionAndCatchForm($interaction)
    }
    
    CloseForm([ClientLogicalForm] $form) {
        $this.InvokeInteraction((New-Object CloseFormInteraction -ArgumentList $form))
    }
    
    [ClientLogicalForm[]]GetAllForms() {
        $forms = @()
        foreach ($form in $this.clientSession.OpenedForms) {
            $forms += $form
        }
        return $forms
    }
    
    [string]GetErrorFromErrorForm() {
        $errorText = ""
        $this.GetAllForms() | % {
            $form = $_
            if ( $form.ControlIdentifier -eq "00000000-0000-0000-0800-0000836bd2d2" ) {
                $form.ContainedControls | Where-Object { $_ -is [ClientStaticStringControl] } | % {
                    $errorText = $_.StringValue
                }
            }
        }
        return $errorText
    }
    
    [string]GetWarningFromWarningForm() {
        $warningText = ""
        $this.GetAllForms() | % {
            $form = $_
            if ( $form.ControlIdentifier -eq "00000000-0000-0000-0300-0000836bd2d2" ) {
                $form.ContainedControls | Where-Object { $_ -is [ClientStaticStringControl] } | % {
                    $warningText = $_.StringValue
                }
            }
        }
        return $warningText
    }

    [Hashtable]GetFormInfo([ClientLogicalForm] $form) {
    
        function Dump-RowControl {
            Param(
                [ClientLogicalControl] $control
            )
            @{
                "$($control.Name)" = $control.ObjectValue
            }
        }
    
        function Dump-Control {
            Param(
                [ClientLogicalControl] $control,
                [int] $indent
            )
    
            $output = @{
                "name" = $control.Name
                "type" = $control.GetType().Name
            }
            if ($control -is [ClientGroupControl]) {
                $output += @{
                    "caption" = $control.Caption
                    "mappingHint" = $control.MappingHint
                }
            } elseif ($control -is [ClientStaticStringControl]) {
                $output += @{
                    "value" = $control.StringValue
                }
            } elseif ($control -is [ClientInt32Control]) {
                $output += @{
                    "value" = $control.ObjectValue
                }
            } elseif ($control -is [ClientStringControl]) {
                $output += @{
                    "value" = $control.stringValue
                }
            } elseif ($control -is [ClientActionControl]) {
                $output += @{
                    "caption" = $control.Caption
                }
            } elseif ($control -is [ClientFilterLogicalControl]) {
            } elseif ($control -is [ClientRepeaterControl]) {
                $output += @{
                    "$($control.name)" = @()
                }
                $index = 0
                while ($true) {
                    if ($index -ge ($control.Offset + $control.DefaultViewport.Count)) {
                        $this.ScrollRepeater($control, 1)
                    }
                    $rowIndex = $index - $control.Offset
                    if ($rowIndex -ge $control.DefaultViewport.Count) {
                        break 
                    }
                    $row = $control.DefaultViewport[$rowIndex]
                    $rowoutput = @{}
                    $row.Children | % { $rowoutput += Dump-RowControl -control $_ }
                    $output[$control.name] += $rowoutput
                    $index++
                }
            }
            else {
            }
            $output
        }
    
        return @{
            "title" = "$($form.Name) $($form.Caption)"
            "controls" = $form.Children | % { Dump-Control -output $output -control $_ -indent 1 }
        }
    }
    
    CloseAllForms() {
        $this.GetAllForms() | % { $this.CloseForm($_) }
    }

    CloseAllErrorForms() {
        $this.GetAllForms() | % {
            if ($_.ControlIdentifier -eq "00000000-0000-0000-0800-0000836bd2d2") {
                $this.CloseForm($_)
            }
        }
    }

    CloseAllWarningOrInfoForms() {
        while ($this.HasWarningOrInfoForms()) {
            $form = $this.clientSession.TopMostInteractiveForm;
            $this.CloseForm($form)
            $this.AwaitState([ClientSessionState]::Ready)
        }
    }

    [bool]HasWarningOrInfoForms() {
        $form = $this.clientSession.TopMostInteractiveForm;
        if($form -eq $null) {
            return $false
        }

        if ($form.ControlIdentifier -eq "00000000-0000-0000-0300-0000836bd2d2" -or $form.MappingHint -eq "InfoDialog") {
            return $true
        }
        return $false
    }
    
    [ClientLogicalControl]GetControlByCaption([ClientLogicalControl] $control, [string] $caption) {
        return $control.ContainedControls | Where-Object { $_.Caption.Replace("&","") -eq $caption } | Select-Object -First 1
    }
    
    [ClientLogicalControl]GetControlByName([ClientLogicalControl] $control, [string] $name) {
        return $control.ContainedControls | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    }
    
    [ClientLogicalControl]GetControlByType([ClientLogicalControl] $control, [Type] $type) {
        return $control.ContainedControls | Where-Object { $_ -is $type } | Select-Object -First 1
    }
    
    SaveValue([ClientLogicalControl] $control, [string] $newValue) {
        $this.InvokeInteraction((New-Object SaveValueInteraction -ArgumentList $control, $newValue))
    }
    
    ScrollRepeater([ClientRepeaterControl] $repeater, [int] $by) {
        $this.InvokeInteraction((New-Object ScrollRepeaterInteraction -ArgumentList $repeater, $by))
    }
    
    ActivateControl([ClientLogicalControl] $control) {
        $this.InvokeInteraction((New-Object ActivateControlInteraction -ArgumentList $control))
    }
    
    [ClientActionControl]GetActionByCaption([ClientLogicalControl] $control, [string] $caption) {
        return $control.ContainedControls | Where-Object { ($_ -is [ClientActionControl]) -and ($_.Caption.Replace("&","") -eq $caption) } | Select-Object -First 1
    }
    
    [ClientActionControl]GetActionByName([ClientLogicalControl] $control, [string] $name) {
        return $control.ContainedControls | Where-Object { ($_ -is [ClientActionControl]) -and ($_.Name -eq $name) } | Select-Object -First 1
    }
    
    InvokeAction([ClientActionControl] $action) {
        $this.InvokeInteraction((New-Object InvokeActionInteraction -ArgumentList $action))
        $this.CloseAllWarningOrInfoForms()
    }
    
    [ClientLogicalForm]InvokeActionAndCatchForm([ClientActionControl] $action) {
        return $this.InvokeInteractionAndCatchForm((New-Object InvokeActionInteraction -ArgumentList $action))
    }
}