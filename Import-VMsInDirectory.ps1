#Requires -RunAsAdministrator
Param (
   [Parameter(Mandatory = $true)] 
   [string] $VMRoot = "D:\Hyper-V"
)

If(Test-Path $VMRoot){
    Write-Host "Path Found: $VMRoot" -ForegroundColor Green
}Else{
    Write-Host "$VMRoot Does not exist" -ForegroundColor Red
    Exit -1
}

If($Files = Get-Childitem –Path $VMRoot -Recurse -Include "*.vmcx"){
    Foreach($File in $Files){
        Write-Host "Importing ""$($File.fullname)"""
	    Import-VM -Path $File.fullname  -Register
    }
}Else{
    Write-Host "No VMCX files where found at ""$VMRoot""" -ForegroundColor Yellow
    Exit -2
}
Write-Host "Import Complete" -ForegroundColor Green