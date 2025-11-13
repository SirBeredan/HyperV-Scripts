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
New-VM -Name $NewVMName -MemoryStartupBytes $VMStartyUpMemory -Generation 2 -Path $OriginalVM.Path -BootDevice NetworkAdapter -SwitchName $VMSwitch -NoVHD -ErrorAction Stop -Verbose

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

$VlanID = (Get-VMNetworkAdapterVlan -VMName $OriginalVMName).AccessVlanId
If($VlanID){
   Write-Host "Setting Vlan ID to $VlanID"
   Set-VMNetworkAdapterVlan -VMName $NewVMName -Access -VlanId $VlanID
}

If(($OriginalVM | Get-VMHardDiskDrive).Path -ilike "*.vhdx"){
    Write-Host "Backing Up $VMVHDX"
    $VMVHDX = ($OriginalVM | Get-VMHardDiskDrive).Path
    Copy-Item $VMVHDX -Destination "$VMVHDX.Old" -verbose
}Else{
    Write-Host "No VHDX found to backup" -foreground Red
    Exit -1
}

If(Test-Path "$env:windir\system32\MBR2GPT.EXE"){
   Write-Host "Mounting $VMVHDX"
   $DiskNumber = (Mount-VHD -Path $VMVHDX -PassThru | Get-Disk).Number
   
   Write-Host "Converting Disk $DiskNumber to GPT "
   Start-Process "$env:windir\system32\MBR2GPT.EXE" -ArgumentList "/convert /allowFullOS /disk:$DiskNumber" -Wait
   
   Write-Host "Dismounting $VMVHDX"
   Dismount-VHD -DiskNumber $DiskNumber
   $AllowedStart = $True
}

Write-Host "Attaching $VMVHDX"
Get-VM $NewVMName | Add-VMHardDiskDrive -Path $VMVHDX

if(!(Get-HgsGuardian UntrustedGuardian -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)){
    #Create Guardian
    Write-Host "Creating UntrustedGuardian"
    New-HgsGuardian UntrustedGuardian -GenerateCertificates
}
#Create Key
Write-Host "Creating KeyProtector"
$Owner = Get-HgsGuardian UntrustedGuardian
$HKP = New-HgsKeyProtector -Owner $Owner -AllowUntrustedRoot

#Add VMKey to VM
Write-Host "Setting KeyProtector on $NewVMName"
Set-VMKeyProtector -VMName $NewVMName -KeyProtector $HKP.RawData
    
#Enable vTPM
Write-Host "Enabling vTPM on $NewVMName"
Enable-VMTPM $NewVMName

If($AllowedStart){
   #Start VM
   Write-Host "Starting $NewVMName" -foreground Green
   Start-VM $NewVMName
}Else{
   Write-Host "MBR2GPT.EXE is missing on this server OS. Please Complete the following" -foreground Yellow
   Write-Host "Starting $OriginalVMName, Please Login once booted" -foreground Yellow
   Start-VM $OriginalVMName
   Write-Host "From Comand Prompt Run the following Commands" -foreground Yellow
   Write-Host "MBR2GPT.EXE /convert /allowFullOS /disk:0"
   Write-Host "shutdown -s -f -t 0"
   Write-Host "Then start $NewVMName" -foreground Yellow
}



