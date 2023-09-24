# Input bindings are passed in via param block.
param($QueueItem, $TriggerMetadata)



# Write out the queue message and insertion time to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"
Write-Host "Queue item insertion time: $($TriggerMetadata.InsertionTime)"
<#
.SYNOPSIS
This is used to process the carbon black files from AWS

.DESCRIPTION
Long description

.EXAMPLE
An example

.NOTES
General notes
#>
function ProcessBucketFiles ()
{
    $time = $env:timeInterval
    $startTime = [System.DateTime]::UtcNow.AddMinutes(-$($time))
    $OrgKey = $env:CarbonBlackOrgKey
    $now = [System.DateTime]::UtcNow
    $workspaceId = $env:workspaceId
    $workspaceSharedKey = $env:workspaceKey
    $AWSAccessKeyId = $env:AWSAccessKeyId
    $AWSSecretAccessKey = $env:AWSSecretAccessKey
    $queueName=$env:queueName
    $carbonBlackStorage=$env:AzureWebJobsStorage
    try {
        GetBucketDetails -s3BucketName $QueueItem["s3BucketName"] -prefixFolder $QueueItem["prefixFolder"] -tableName $QueueItem["tableName"] -logtype $QueueItem["logtype"]
    }
    catch {
        Write-Host "Error, error message: $($Error[0].Exception.Message)"
    }
   
}

    # Function to build the authorization signature to post to Log Analytics
    function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource) {
        $xHeaders = "x-ms-date:" + $date;
        $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource;
        $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash);
        $keyBytes = [Convert]::FromBase64String($sharedKey);
        $sha256 = New-Object System.Security.Cryptography.HMACSHA256;
        $sha256.Key = $keyBytes;
        $calculatedHash = $sha256.ComputeHash($bytesToHash);
        $encodedHash = [Convert]::ToBase64String($calculatedHash);
        $authorization = 'SharedKey {0}:{1}' -f $customerId, $encodedHash;
        return $authorization;
    }
    
# Function to POST the data payload to a Log Analytics workspace
function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType) {
    $TimeStampField = "DateValue"
    $method = "POST";
    $contentType = "application/json";
    $customerId = $customerId
    $resource = "/api/logs";
    $rfc1123date = [DateTime]::UtcNow.ToString("r");
    $contentLength = $body.Length;
    $signature = Build-Signature -customerId $customerId -sharedKey $sharedKey -date $rfc1123date -contentLength $contentLength -method $method -contentType $contentType -resource $resource;
    if ([string]::IsNullOrEmpty($logAnalyticsUri)) {
        $logAnalyticsUri = "https://" + $customerId + ".ods.opinsights.azure.com"
    }
    # Returning if the Log Analytics Uri is in incorrect format.
    # Sample format supported: https://" + $customerId + ".ods.opinsights.azure.com
    if ($logAnalyticsUri -notmatch 'https:\/\/([\w\-]+)\.ods\.opinsights\.azure.([a-zA-Z\.]+)$') {
        throw "Netskope: Invalid Log Analytics Uri."
    }
    $logAnalyticsUri = $logAnalyticsUri + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization"        = $signature;
        "Log-Type"             = $logType;
        "x-ms-date"            = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    };
    $response = Invoke-WebRequest -Body $body -Uri $logAnalyticsUri -Method $method -ContentType $contentType -Headers $headers -UseBasicParsing
    return $response.StatusCode
}

Function EventsFieldsMapping {
    Param (
        $events
    )
    Write-Host "Started Field Mapping for event logs"

    $fieldMappings = @{
        'shortDescription' = 'event_description'
        'createTime' = 'backend_timestamp'
        'eventId' = 'event_id'
        'longDescription' = 'event_description'
        'eventTime' = 'device_timestamp'
        'securityEventCode' = 'alert_id'
        'eventType' = 'type'
        'incidentId' = 'alert_id'
        'deviceDetails_deviceIpAddress' = 'device_external_ip'
        'deviceDetails_deviceIpV4Address' = 'device_external_ip'
        'deviceDetails_deviceId' = 'device_id'
        'deviceDetails_deviceName' = 'device_name'
        'deviceDetails_deviceType' = 'device_os'
        'deviceDetails_msmGroupName' = 'device_group'
        'netFlow_peerFqdn' = 'netconn_domain'
        'netFlow_peerIpAddress' = 'remote_ip'
        'processDetails_name' = 'process_name'
        'processDetails_commandLine' = 'process_cmdline'
        'processDetails_fullUserName' ='process_username'
        'processDetails_processId'='process_pid'
        'processDetails_parentCommandLine' = 'process_cmdline'
        'processDetails_parentName' = 'parent_path'
        'processDetails_parentPid' = 'parent_pid'
        'processDetails_targetCommandLine' = 'target_cmdline'
    }

    $fieldMappings.GetEnumerator() | ForEach-Object {
        if (!$events.ContainsKey($_.Name))
        {
            $events[$_.Name] = $events[$_.Value]
        }
    }
}

Function AlertsFieldsMapping {
    Param (
        $alerts
    )
    Write-Host "Started Field Mapping for alert logs"

    $fieldMappings = @{
        'threatHunterInfo_summary' = 'reason_code'
        'threatHunterInfo_time' = 'create_time'
        'threatHunterInfo_indicators' = 'threat_indicators'
        'threatHunterInfo_count' = '0'
        'threatHunterInfo_dismissed' = 'workflow.state'
        'threatHunterInfo_firstActivityTime' = 'first_event_time'
        'threatHunterInfo_policyId' = 'process_guid'
        'threatHunterInfo_processPath' = 'severity'
        'threatHunterInfo_reportName' = 'report_name'
        'threatHunterInfo_reportId' = 'report_id'
        'threatHunterInfo_reputation' = 'threat_cause_reputation'
        'threatHunterInfo_responseAlarmId' = 'id'
        'threatHunterInfo_responseSeverity' = 'Severity'
        'threatHunterInfo_runState' = 'run_state'
        "threatHunterInfo_sha256_" = "threat_cause_actor_sha256"
        "threatHunterInfo_status" = "status"
        "threatHunterInfo_targetPriority" = "target_value"
        "threatHunterInfo_threatCause_reputation" = "threat_cause_reputation"
        "threatHunterInfo_threatCause_actor" = "threat_cause_actor_sha256"
        "threatHunterInfo_threatCause_actorName" = "threat_cause_actor_name"
        "threatHunterInfo_threatCause_reason" = "reason_code"
        "threatHunterInfo_threatCause_threatCategory" = "threat_cause_threat_category"
        "threatHunterInfo_threatCause_originSourceType" = "threat_cause_vector"
        "threatHunterInfo_threatId" = "threat_id"
        "threatHunterInfo_lastUpdatedTime" = "last_update_time"
        #"threatHunterInfo_orgId_d": "12261",
        "threatInfo_incidentId" = "legacy_alert_id"
        "threatInfo_score" = "severity"
        "threatInfo_summary" = "reason"
        #"threatInfo_time_d": "null",
        "threatInfo_indicators" = "threat_indicators"
        "threatInfo_threatCause_reputation" = "threat_cause_reputation"
        "threatInfo_threatCause_actor" = "threat_cause_actor_sha256"
        "threatInfo_threatCause_reason" = "reason_code"
        "threatInfo_threatCause_threatCategory" = "threat_cause_threat_catego"
        "threatInfo_threatCause_actorProcessPPid" = "threat_cause_actor_process_pid"
        "threatInfo_threatCause_causeEventId" = "threat_cause_cause_event_id"
        "threatInfo_threatCause_originSourceType" = "threat_cause_vector"
        "url" = "alert_url"
        "eventTime" = "create_time"
        #"eventDescription_s": "[AzureSentinel] [Carbon Black has detected a threat against your company.] [https://defense-prod05.conferdeploy.net#device/20602996/incident/NE2F3D55-013a6074-000013b0-00000000-1d634654ecf865f-GUWNtEmJQhKmuOTxoRV8hA-6e5ae551-1cbb-45b3-b7a1-1569c0458f6b] [Process powershell.exe was detected by the report \"Execution - Powershell Execution With Unrestriced or Bypass Flags Detected\" in watchlist \"Carbon Black Endpoint Visibility\"] [Incident id: NE2F3D55-013a6074-000013b0-00000000-1d634654ecf865f-GUWNtEmJQhKmuOTxoRV8hA-6e5ae551-1cbb-45b3-b7a1-1569c0458f6b] [Threat score: 6] [Group: Standard] [Email: sanitized@sanitized.com] [Name: Endpoint2] [Type and OS: WINDOWS pscr-sensor] [Severity: 6]\n",
        "deviceInfo_deviceId" = "device_id"
        "deviceInfo_deviceName" = "device_name"
        "deviceInfo_groupName" = "policy_name"
        "deviceInfo_email" = "device_username"
        "deviceInfo_deviceType" = "device_os"
        "deviceInfo_deviceVersion" = "device_os_version"
        "deviceInfo_targetPriorityType" = "target_value"
       # "deviceInfo_targetPriorityCode_d": "0",
        "deviceInfo_uemId" = "device_uem_id"
        "deviceInfo_internalIpAddress" = "device_internal_ip"
        "deviceInfo_externalIpAddress" = "device_external_ip"
    }

    $fieldMappings.GetEnumerator() | ForEach-Object {
        if (!$alerts.ContainsKey($_.Name))
        {
            $alerts[$_.Name] = $alerts[$_.Value]
        }
    }
}
<#
.SYNOPSIS
This method is extract the GZ file format

.DESCRIPTION
Long description

.PARAMETER infile
Parameter description

.PARAMETER outfile
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>
Function Expand-GZipFile {
    Param(
        $infile,
        $outfile
    )
	Write-Host "Processing Expand-GZipFile for: infile = $infile, outfile = $outfile"
    $inputfile = New-Object System.IO.FileStream $infile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
    $output = New-Object System.IO.FileStream $outfile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
    $gzipStream = New-Object System.IO.Compression.GzipStream $inputfile, ([IO.Compression.CompressionMode]::Decompress)

    $buffer = New-Object byte[](1024)
    while ($true) {
        $read = $gzipstream.Read($buffer, 0, 1024)
        if ($read -le 0) { break }
		$output.Write($buffer, 0, $read)
	}

    $gzipStream.Close()
    $output.Close()
    $inputfile.Close()
}

<#
.SYNOPSIS
This method is used to split the data based on size and post to log analytics work space

.DESCRIPTION
Long description

.PARAMETER customerId
Parameter description

.PARAMETER sharedKey
Parameter description

.PARAMETER payload
Parameter description

.PARAMETER logType
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>
function SplitDataAndProcess($customerId, $sharedKey, $payload, $logType) {
    $tempdata = @()
    $tempdataLength = 0
    $tempDataSize = 0
    $StartTime = (Get-Date).ToUniversalTime()
    try {
        if ((($payload |  Convertto-json -depth 3).Length) -gt 25MB) {
            Write-Host "Upload is over 25MB, needs to be split"
            foreach ($record in $payload) {
                $tempdata += $record
                $tempdataLength = $tempdata.Count
                $tempDataSize += ($record  | ConvertTo-Json).Length
                if ($tempDataSize -gt 25MB) {
                    write-Host "Sending data to log analytics when data size = $TempDataSize greater than 25mb post chuncking the data and length of events = $tempdataLength"
                    $responseCode = Post-LogAnalyticsData -customerId $customerId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes(($tempdata | ConvertTo-Json))) -logType $logType
                    Write-Host "Post-LogAnalyticsData response code is $($responseCode) for LogType : $($logType)"
                    $tempdata = $null
                    $tempdata = @()
                    $tempDataSize = 0
                    $tempdataLength = 0
                }
            }
            Write-Host "Sending left over data = $Tempdatasize after all the chuncking of done is completed. Now datasize will be < 25mb and length of events = $tempdataLength"
            $responseCode = Post-LogAnalyticsData -customerId $customerId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes(($tempdata | ConvertTo-Json))) -logType $logType
            $elapsedTime = (Get-Date).ToUniversalTime() - $StartTime
        }
        $totalTime = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks)
        Write-Host "Total Time taken to Split and Process this data = $totalTime"
        return $responseCode
    }
    catch {
        Write-Host "Error, error message: $($Error[0].Exception.Message)"
    }
}   

<#
.SYNOPSIS
This is used to process the carbon black data

.DESCRIPTION
Long description

.PARAMETER alleventobjs
Parameter description

.PARAMETER logtype
Parameter description

.PARAMETER endTime
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>
 function ProcessData($alleventobjs, $logtype, $endTime) {
    Write-Host "Process Data function:- EventsLength - $($allEventsLength), Logtype - $($logtype) and Endtime - $($endTime)"
    $customerId = $env:workspaceId
    $sharedKey = $env:workspacekey
    $responseCode = 200
    if ($alleventobjs -ne $null) {
        $jsonPayload = $alleventobjs | ConvertTo-Json -Depth 3
        $mbytes = ([System.Text.Encoding]::UTF8.GetBytes($jsonPayload)).Count / 1024 / 1024
        Write-Host "Total mbytes :- $($mbytes) for type :- $($logtype)"
        # Check the payload size, if under 30MB post to Log Analytics.
        if (($mbytes -le 30)) {
            $responseCode = Post-LogAnalyticsData -customerId $customerId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($jsonPayload)) -logType $tableName
            if($responseCode -eq 200){
                Write-Host "SUCCESS: $allEventsLength total '$logType' events posted to Log Analytics: $mbytes MB" -ForegroundColor Green
                DeleteMessageFromQueue
            
            }
        }
        else {
            Write-Host "Warning!: Total data size is > 30mb hence performing the operation of split and process."
            $responseCode = SplitDataAndProcess -customerId $customerId -sharedKey $sharedKey -payload $alleventobjs -logType $tableName
        }
    }
    else {
        $startInterval = (Get-Date 01.01.1970) + ([System.TimeSpan]::fromseconds($startTime))
        $endInterval = (Get-Date 01.01.1970) + ([System.TimeSpan]::fromseconds($endTime))
        Write-Host "INFO: No new '$logtype' records created between $startInterval and $endInterval"
    }
    return $responseCode
}
<#
.SYNOPSIS
This method is used to delete message from queue

.DESCRIPTION
Long description

.EXAMPLE
An example

.NOTES
General notes
#>
function  DeleteMessageFromQueue()
{
    $ctx = New-AzStorageContext -ConnectionString $carbonBlackStorage
    if ($ctx -ne $null)
    {
      $queue = Get-AzStorageQueue –Name $queueName –Context $ctx
    }
    else
    {
      Write-Host "Storage context not available"
    }
    if ($queue -ne $null) 
    {  
       
       $status= $queue.CloudQueue.DeleteMessageAsync($TriggerMetadata.Id,$TriggerMetadata.PopReceipt).GetAwaiter().GetResult()

       if($status -ne $null)
       {
         Write-Host "Message Deleted successfully"
       }

    }
    else
    {
      Write-Host "unable to get queue details"
    }
}
<#
.SYNOPSIS
This method is used to get the bucket details i.e. carbon black cloud files from AWS

.DESCRIPTION
Long description

.PARAMETER s3BucketName
Parameter description

.PARAMETER prefixFolder
Parameter description

.PARAMETER tableName
Parameter description

.PARAMETER logtype
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>
function  GetBucketDetails {
    param (
        $s3BucketName,
        $prefixFolder,
        $tableName,
        $logtype
    )
    
  
    IF ($Null -ne $s3BucketName) {
        Set-AWSCredentials -AccessKey $AWSAccessKeyId -SecretKey $AWSSecretAccessKey
        while ($startTime -le $now) {
            $keyPrefix = "$prefixFolder/org_key=$OrgKey/year=$($startTime.Year)/month=$($startTime.Month)/day=$($startTime.Day)/hour=$($startTime.Hour)/minute=$($startTime.Minute)"
            #$keyPrefix="carbon-black-events/org_key=7DESJ9GN/year=2023/month=9/day=6/hour=13/minute=46"
            
            Get-S3Object -BucketName $s3BucketName -keyPrefix $keyPrefix | Read-S3Object -Folder "C:\tmp"
            Write-Host "Files under $keyPrefix are downloaded."

            if (Test-Path -Path "/tmp/$keyPrefix") {
                Get-ChildItem -Path "/tmp" -Recurse -Include *.gz |
                Foreach-Object {
                    $filename = $_.FullName
                    $infile = $_.FullName
                    $outfile = $_.FullName -replace ($_.Extension, '')
                    Expand-GZipFile $infile.Trim() $outfile.Trim()
                    $null = Remove-Item -Path $infile -Force -Recurse -ErrorAction Ignore
                    $filename = $filename -replace ($_.Extension, '')
                    $filename = $filename.Trim()
                    $AllEvents = [System.Collections.ArrayList]::new()

                    foreach ($logEvent in [System.IO.File]::ReadLines($filename))
                    {
                        $logs = $logEvent | ConvertFrom-Json
                        $hash = @{}
                        $logs.psobject.properties | foreach{$hash[$_.Name]= $_.Value}
                        $logevents = $hash

                        if($logtype -eq "event")
                        {
                            EventsFieldsMapping -events $logevents
                        }
                        if($logtype -eq "alert")
                        {
                            AlertsFieldsMapping -alerts $logevents
                        }
                        $AllEvents.Add($logevents)
                    }

                    $EventLogsJSON = $AllEvents

                    if (-not([string]::IsNullOrWhiteSpace($EventLogsJSON)))
                    {
                        try {
                            $responseCode = ProcessData -alleventobjs $EventLogsJSON -logtype $tableName -endTime $now
                            Write-Host "Pushed events to $($tableName)"
                        }
                        catch {
                            $string_err = $_ | Out-String
                            Write-Host $string_err
                        }
                        Write-Host("$($responseObj.count) new Carbon Black Events as of $([DateTime]::UtcNow). Pushed data to Azure sentinel Status code:$($status)")
                    }
                    $null = Remove-Variable -Name AllEvents
                }

                Remove-Item -LiteralPath "/tmp/$keyPrefix" -Force -Recurse
            }

            $startTime = $startTime.AddMinutes(1)
        }
    }
}

ProcessBucketFiles