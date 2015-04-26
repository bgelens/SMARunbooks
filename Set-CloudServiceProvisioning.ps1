workflow Set-CloudServiceProvisioning {
    [OutputType([PSCustomObject])]

    param (
        [Parameter(Mandatory)]
        [string] $VMRoleID,

        [Parameter(Mandatory)]
        [string] $VMMServer,

        [Parameter(Mandatory)]
        [pscredential] $VMMCreds,

        [string] $ServiceInstanceId,

        [bool] $Enable
    )

    $OutputObj = [PSCustomObject] @{}

    $ErrorActionPreference = 'Stop'
    Write-Verbose -Message 'Running Runbook: Set-CloudServiceProvisioning'
    Write-Verbose -Message "VMRoleID: $VMRoleID"
    Write-Verbose -Message "VMMServer: $VMMServer"
    Write-Verbose -Message "VMMCreds: $($VMMCreds.UserName)"

    try {
        if ($Enable -eq $false) {
            if (-not $ServiceInstanceId) {
                throw 'ServiceInstanceId not present, cannot update table to provisioned state'
            }
            Add-Member -InputObject $OutputObj -MemberType NoteProperty -Name 'ServiceInstanceId' -Value $ServiceInstanceId
        }
        Add-Member -InputObject $OutputObj -MemberType NoteProperty -Name 'VMRoleID' -Value $VMRoleID

        Write-Verbose -Message 'Checking if VMM is clustered'
        $ActiveNode = inlinescript {
            $ErrorActionPreference = 'Stop'
            $VerbosePreference = [System.Management.Automation.ActionPreference]$Using:VerbosePreference
            $DebugPreference = [System.Management.Automation.ActionPreference]$Using:DebugPreference 
            Write-Verbose -Message 'Loading VMM Environmental data'
            $VMM = Get-SCVMMServer -ComputerName $Using:VMMServer
            if ($VMM.IsHighlyAvailable) {
                return $VMM.ActiveVMMNode
            }
            else {
                return $using:VMMServer
            }
        } -PSComputerName $VMMServer -PSCredential $VMMCreds -PSRequiredModules VirtualMachineManager

        Write-Verbose -Message 'Configuring CloudService provisioning status'
        $Result = inlinescript {
            $ErrorActionPreference = 'Stop'
            $VerbosePreference = [System.Management.Automation.ActionPreference]$Using:VerbosePreference
            $DebugPreference = [System.Management.Automation.ActionPreference]$Using:DebugPreference 

            Write-Verbose -Message 'Loading VMM Environmental data'
            $VMMConn = Get-SCVMMServer -ComputerName $Using:VMMServer

            $Resource = Get-CloudResource -Id $using:VMRoleID
            $ConnectionTimeout = 15
            $QueryTimeout = 600
            $BatchSize = 50000
            $ConnectionString = 'Server={0};Database={1};Integrated Security=True;Connect Timeout={2}' -f $VMMConn.DatabaseInstanceName, $VMMConn.DatabaseName, $ConnectionTimeout 
            $conn = New-Object -TypeName System.Data.SqlClient.SQLConnection
            $conn.ConnectionString = $ConnectionString
            $conn.Open()

            if ($using:Enable) {
                Write-Verbose -Message 'Enable Provisioning status'
                $TSQL = @"
                update dbo.tbl_WLC_ServiceInstance
                Set ObjectState = 6, VMRoleID = NULL
                OUTPUT INSERTED.ServiceInstanceId
                where VmRoleID = '$using:VMRoleID'
"@
                $command = New-Object -TypeName System.Data.SqlClient.SqlCommand
                $command.Connection = $conn
                $command.CommandText = $TSQL
                $reader = $command.ExecuteReader()
                while ($reader.Read()) {
                    $output = $reader.GetValue($1)
                }
                Write-Output -InputObject $output.GUID
            }

            else {
                Write-Verbose -Message 'Disable Provisioning status'
                $TSQL = @"
            update dbo.tbl_WLC_ServiceInstance
            Set ObjectState = 1, VMRoleID = '$using:VMRoleID'
            where ServiceInstanceId = '$using:ServiceInstanceId'
"@


                $command = New-Object -TypeName System.Data.SqlClient.SqlCommand
                $command.Connection = $conn
                $command.CommandText = $TSQL
                $null = $command.ExecuteNonQuery()
            }
           
            $conn.Close()
            $conn.Dispose()

            $null = Get-CloudService -ID $Resource.CloudServiceId | Set-CloudService -RunREST
        } -PSComputerName $ActiveNode -PSCredential $VMMCreds -PSRequiredModules VirtualMachineManager -PSAuthentication CredSSP
    }
    catch {
        Add-Member -InputObject $OutputObj -MemberType NoteProperty -Name 'error' -Value $_.message
    }

    if ($Enable) {
        Add-Member -InputObject $OutputObj -MemberType NoteProperty -Name 'ServiceInstanceId' -Value $Result
    }
    return $OutputObj
}