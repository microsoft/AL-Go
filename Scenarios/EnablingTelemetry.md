# 15. Enabling telemetry

If you want to enable partner telemetry add your Application Insights connection string to the AL-GO settings file. Simply add the following setting to your settings file:

```
"PartnerTelemetryConnectionString":  "<connection string to your Application Insights>"
```

Per default, AL-Go logs some basic telemetry to Microsoft. If you want to opt-out of sending telemetry to Microsoft you can add the following setting to your settings file:

```
"microsoftTelemetryConnectionString":  ""
```

By setting the Microsoft telemetry connection string to be an empty string you opt-out of sending basic telemetry to Microsoft. If on the other hand you want to send extended telemetry to Microsoft you can do that with the following setting.

```
"SendExtendedTelemetryToMicrosoft" : true
```

Sending extended telemetry to Microsoft is helpful for when we need to help investigate an issue in your repository.

______________________________________________________________________

[back](../README.md)
