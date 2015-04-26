workflow Get-VMKVPValue {
    [OutputType([PSCustomObject])]

    param (
        [Parameter(Mandatory)]
        [string] $HyperVHost,

        [Parameter(Mandatory)]
        [Pscredential] $HyperVCred,

        [Parameter(Mandatory)]
        [String] $VMName,

        [Parameter(Mandatory)]
        [String] $Key,

        [Parameter(Mandatory)]
        [String] $Value
    )

    $OutputObj = [PSCustomObject] @{}

    $ErrorActionPreference = 'Stop'
    Write-Verbose -Message 'Running Runbook: Get-VMKVPValue'
    Write-Verbose -Message "HyperVHost: $HyperVHost"
    Write-Verbose -Message "HyperVCred: $($HyperVCred.UserName)"
    Write-Verbose -Message "VMName: $VMName"
    Write-Verbose -Message "Key: $Key"
    Write-Verbose -Message "Value: $Value"

    try {
        $Result = inlinescript {
            $VerbosePreference = [System.Management.Automation.ActionPreference]$Using:VerbosePreference
            $DebugPreference = [System.Management.Automation.ActionPreference]$Using:DebugPreference 

            Write-Verbose -Message "Setting up CIMSession with Hyper-V host: $using:HyperVHost"
            $CimSession = New-CimSession -ComputerName $using:HyperVHost -Credential $using:HyperVCred

            function Get-KVPValue {
                param (
                    $CimSession,
                    $VMName,
                    $Key
                )

                Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_ComputerSystem -Filter "elementname = '$VMName'" -CimSession $CimSession | 
                    Get-CimAssociatedInstance -ResultClassName Msvm_KvpExchangeComponent |  ForEach-Object {
                        $_ | Select-Object -ExpandProperty GuestExchangeItems |  ForEach-Object {
                                $XML = ([XML]$_).INSTANCE.PROPERTY
                                if (($XML| Where-Object { $_.Name -eq 'Name' }).value -eq $Key) {
                                    ($XML | Where-Object { $_.Name -eq 'Data' }).value
                                }
                            }
                        }
            } # function Get-KVPValue

            while (($V = Get-KVPValue -CimSession $CimSession -VMName $using:VMName -Key $using:Key) -ne $using:Value) {
                Start-Sleep -Seconds 5
            }
            Write-Output -InputObject $V
            $CimSession | Remove-CimSession

        } -PSComputerName $HyperVHost -PSCredential $HyperVCred
        Add-Member -InputObject $OutputObj -MemberType NoteProperty -Name 'VMName' -Value $VMName
        Add-Member -InputObject $OutputObj -MemberType NoteProperty -Name 'Key' -Value $Key
        Add-Member -InputObject $OutputObj -MemberType NoteProperty -Name 'Value' -Value $Result
    }
    catch {
        Add-Member -InputObject $OutputObj -MemberType NoteProperty -Name 'error' -Value $_.message
    }
    return $OutputObj
}