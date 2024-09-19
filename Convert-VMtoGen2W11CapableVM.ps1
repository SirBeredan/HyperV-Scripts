Param (
   [Parameter(Mandatory = $true)] 
   [string] $OriginalVMName
)

if($OriginalVM = Get-VM $OriginalVMName){$OriginalVM}Else{Write-Host "$OriginalVMName Does not exist"; Exit -1}
$OriginalVM | Stop-VM -Force
$NewVMName = "$($OriginalVM.Name) Gen2"
$NewVMMac = ($OriginalVM | Get-VMNetworkAdapter).MacAddress
$VMSwitch = ($OriginalVM | Get-VMNetworkAdapter).SwitchName
$vCPUCount = if($OriginalVM.ProcessorCount -eq 1){"2"}Else{$OriginalVM.ProcessorCount}
$VMStartyUpMemory = if($OriginalVM.MemoryStartup -le 4294967296){4294967296}Else{$OriginalVM.MemoryStartup}

Write-Host "Creating VM"
New-VM -Name $NewVMName -MemoryStartupBytes $VMStartyUpMemory -Generation 2 -Path $OriginalVM.Path -BootDevice NetworkAdapter -SwitchName $VMSwitch -NoVHD -ErrorAction Stop –Verbose

Write-Host "Setting Common Settings"
Set-VM -Name $NewVMName -ProcessorCount $vCPUCount -SmartPagingFilePath $OriginalVM.SmartPagingFilePath -SnapshotFileLocation $OriginalVM.SnapshotFileLocation -AutomaticStartAction $OriginalVM.AutomaticStartAction -AutomaticStopAction $OriginalVM.AutomaticStartAction -Notes $OriginalVM.Notes

if($OriginalVM.DynamicMemoryEnabled -eq $true){
    Write-Host "Original VM had dynamic memory, Mirroring."
    Set-VM -Name $NewVMName -DynamicMemory $true -MemoryMinimumBytes $OriginalVM.MemoryMinimum -MemoryMaximumBytes $OriginalVM.MemoryMaximum 
}

if($OriginalVM | Get-VMDvdDrive){
    Write-Host "Original VM Had a DVD, Creating"
    if(($OriginalVM | Get-VMDvdDrive).Path){
        Write-Host "Original VM Mounted an ISO, setting to ISO"
        Get-VM $NewVMName | Add-VMDvdDrive -Path ($OriginalVM | Get-VMDvdDrive).Path
    }Else{
        Get-VM $NewVMName | Add-VMDvdDrive
    }
}

Write-Host "Enable Intergration Services"
Get-VMIntegrationService -VMName $NewVMName | Enable-VMIntegrationService

Write-Host "Set Mac Address to $NewVMMac"
Set-VMNetworkAdapter -VMName $NewVMName -StaticMacAddress $NewVMMac

If(($OriginalVM | Get-VMHardDiskDrive).Path -ilike "*.vhdx"){
    $VMVHDX = ($OriginalVM | Get-VMHardDiskDrive).Path
    Copy-Item $VMVHDX -Destination "$VMVHDX.Old"
}

$DiskNumber = (Mount-VHD -Path ($OriginalVM | Get-VMHardDiskDrive).Path -PassThru | Get-Disk).Number
Start-Process "$env:windir\system32\MBR2GPT.EXE" -ArgumentList "/convert /allowFullOS /disk:$DiskNumber" -Wait
Dismount-VHD -DiskNumber $DiskNumber
Get-VM $NewVMName | Add-VMHardDiskDrive -Path ($OriginalVM | Get-VMHardDiskDrive).Path

if(!(Get-HgsGuardian UntrustedGuardian -ErrorAction SilentlyContinue -WarningAction SilentlyContinue))
{
    #Create Guardian
    New-HgsGuardian UntrustedGuardian -GenerateCertificates
}
#Create Key
$Owner = Get-HgsGuardian UntrustedGuardian
$HKP = New-HgsKeyProtector -Owner $Owner -AllowUntrustedRoot

#Add VMKey to VM
Set-VMKeyProtector -VMName $NewVMName -KeyProtector $HKP.RawData
    
#Enable vTPM
Enable-VMTPM $NewVMName

#Start VM
Start-VM $NewVMName