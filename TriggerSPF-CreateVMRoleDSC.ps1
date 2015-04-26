workflow TriggerSPF-CreateVMRoleDSC {
    param (
        [Parameter(Mandatory=$true)]
        [PSObject]$ResourceObject,

        [Parameter(Mandatory=$true)]
        [PSObject]$Params,

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

    $WaitJob = Wait-VMMJob -VMMJobId $VMMJobId -VMMServer $VMMServer -VMMCreds $VMMCreds
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

    $ProvisioningEnable = Set-CloudServiceProvisioning -VMRoleID $ResourceObject.id `
                                                       -VMMServer $VMMServer `
                                                       -VMMCreds $VMMCreds `
                                                       -Enable $true
    
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
    }

    $ProvisioningDisable = Set-CloudServiceProvisioning -VMRoleID $ResourceObject.id `
                                                        -VMMServer $VMMServer `
                                                        -VMMCreds $VMMCreds `
                                                        -Enable $false `
                                                        -ServiceInstanceId $ProvisioningEnable.ServiceInstanceId

    if ($ProvisioningDisable.error) {
        #terminating exception
        Write-Error -Message "Error occured while running Set-CloudServiceProvisioning runbook $($ProvisioningDisable.error)" -ErrorAction Continue
        return
    }
}