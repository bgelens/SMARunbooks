﻿workflow TriggerSPF-CreateVMRoleDSC {

    param (
        [Parameter(Mandatory=$true)]
        [Object]$ResourceObject,

        [Parameter(Mandatory=$true)]
        [Object]$Params,

        [Parameter(Mandatory=$true)]
        [String]$VMMJobId
    )

    $VMMCreds = Get-AutomationPSCredential -Name 'SCVMM Service Account'
    $VMMServer = Get-AutomationVariable -Name 'VMMServer'
    
    
    $VMRoleVMs = Get-VMRoleVMs -VMRoleId $ResourceObject.id -VMMCreds $VMMCreds -VMMServer $VMMServer
    if ($VMRoleVMs.error) {
        #terminating exception
        Write-Error -Message "Error occured while running Get-VMRoleVMs runbook $($VMRoleVMs.error)" -ErrorAction Continue
        return
    }
    Write-Output -InputObject $VMRoleVMs

    $WaitJob = Wait-VMMJob -VMMJobId $VMMJobId -VMMServer $VMMServer -VMMCreds $VMMCreds

    Write-Output -InputObject $WaitJob
    if ($WaitJob.error) {
        #terminating exception
        Write-Error -Message "Error occured while running Wait-VMMJob runbook $($WaitJob.error)" -ErrorAction Continue
        return
    }

    if ($WaitJob.Status -notlike 'Completed*') {
        #cleanup action
        Write-Error -Message "VMMJob was not successfully completed: $($WaitJob.Status)" -ErrorAction Continue
        return
    }

    SendMail -Body '<h1>Time to check on WAPack!</h1>' `
             -Subject 'SMA Update - Enabling Provisioning Status in 120 seconds' `
             -To 'ben.gelens@inovativ.nl'

    Start-Sleep -Seconds 120

    $ProvisioningEnable = Set-CloudServiceStatus -VMRoleID $ResourceObject.id `
                                                 -VMMServer $VMMServer `
                                                 -VMMCreds $VMMCreds `
                                                 -Provisioning $true
    
    Write-Output -InputObject $ProvisioningEnable

    if ($ProvisioningEnable.error) {
        #terminating exception
        Write-Error -Message "Error occured while running Set-CloudServiceProvisioning runbook $($ProvisioningEnable.error)" -ErrorAction Continue
        return
    }

    foreach ($VM in $VMRoleVMs.VMs) {
        $KVP = Wait-VMKVPValue -HyperVHost $VM.VMHost -HyperVCred $VMMCreds -VMName $VM.Name -Key 'LCMStatus' -Value 'Finished'
        if ($KVP.error) {
            Write-Error -Message "Error occured while running Wait-VMKVPValue runbook for $VM.name - $($KVP.error)" -ErrorAction Continue
        }
        Write-Output -InputObject $KVP
    }

    SendMail -Body "<h1>Time to check on WAPack!</h1><br>
                    Key: $KVP.Key<br>
                    Value: $KVP.Value" `
             -Subject 'SMA Update - Disabling Provisioning Status in 120 seconds' `
             -To 'ben.gelens@inovativ.nl'

    Start-Sleep -Seconds 120

    $ProvisioningDisable = Set-CloudServiceStatus -VMRoleID $ResourceObject.id `
                                                  -VMMServer $VMMServer `
                                                  -VMMCreds $VMMCreds `
                                                  -Provisioned $true `
                                                  -ServiceInstanceId $ProvisioningEnable.ServiceInstanceId
    
    Write-Output -InputObject $ProvisioningDisable

    if ($ProvisioningDisable.error) {
        #terminating exception
        Write-Error -Message "Error occured while running Set-CloudServiceProvisioning runbook $($ProvisioningDisable.error)" -ErrorAction Continue
        return
    }
}