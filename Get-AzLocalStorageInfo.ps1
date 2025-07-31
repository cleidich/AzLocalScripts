#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Gathers storage information from Azure Local cluster nodes.

.DESCRIPTION
    This script collects detailed information about physical disks and virtual disks (CSVs) 
    in an Azure Local cluster. Physical disks are grouped by their host node, and virtual 
    disk information focuses on Cluster Shared Volumes.

.PARAMETER OutputFormat
    Specifies the output format. Valid values are 'Table', 'List', or 'CSV'.

.PARAMETER ExportPath
    Optional path to export the results to CSV files.

.PARAMETER IncludeVolumeInfo
    Switch to include volume information for CSV virtual disks.

.EXAMPLE
    .\Get-AzLocalStorageInfo.ps1
    
.EXAMPLE
    .\Get-AzLocalStorageInfo.ps1 -OutputFormat CSV -ExportPath "C:\Reports"
    
.EXAMPLE
    .\Get-AzLocalStorageInfo.ps1 -IncludeVolumeInfo
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'List', 'CSV')]
    [string]$OutputFormat = 'Table',
    
    [Parameter(Mandatory = $false)]
    [string]$ExportPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeVolumeInfo
)

function Convert-BytesToTB {
    param([long]$Bytes)
    return [math]::Round($Bytes / 1TB, 2)
}

function Get-PhysicalDiskInfo {
    Write-Host "Gathering physical disk information..." -ForegroundColor Green
    
    try {
        $physicalDisks = Get-PhysicalDisk | Where-Object { $_.BusType -ne 'Unknown' -and $_.Description -ne $null -and $_.Description.Trim() -ne '' }
        $physicalDiskData = @()
        
        foreach ($disk in $physicalDisks) {
            $diskInfo = [PSCustomObject]@{
                Host = $disk.Description
                UniqueID = $disk.UniqueId
                FriendlyName = $disk.FriendlyName
                Model = $disk.Model
                PhysicalLocation = $disk.PhysicalLocation
                DeviceId = $disk.DeviceId
                LogicalSectorSize = $disk.LogicalSectorSize
                PhysicalSectorSize = $disk.PhysicalSectorSize
                SizeGB = [math]::Round($disk.Size / 1GB, 2)
                SizeTB = Convert-BytesToTB -Bytes $disk.Size
                MediaType = $disk.MediaType
                HealthStatus = $disk.HealthStatus
                OperationalStatus = $disk.OperationalStatus
            }
            $physicalDiskData += $diskInfo
        }
        
        # Group by host
        $groupedByHost = $physicalDiskData | Group-Object -Property Host
        
        return @{
            AllDisks = $physicalDiskData
            GroupedByHost = $groupedByHost
        }
    }
    catch {
        Write-Error "Failed to gather physical disk information: $($_.Exception.Message)"
        return $null
    }
}

function Get-VirtualDiskInfo {
    param([switch]$IncludeVolumes)
    
    Write-Host "Gathering virtual disk information (CSV focus)..." -ForegroundColor Green
    
    try {
        $virtualDisks = Get-VirtualDisk
        $virtualDiskData = @()
        
        foreach ($vdisk in $virtualDisks) {
            # Get associated volume information to identify CSVs
            $volume = $null
            if ($IncludeVolumes) {
                try {
                    $volume = Get-Volume | Where-Object { 
                        $_.FileSystemLabel -eq $vdisk.FriendlyName -or
                        $_.FileSystemLabel -like "*$($vdisk.FriendlyName)*"
                    }
                }
                catch {
                    Write-Warning "Could not retrieve volume info for virtual disk: $($vdisk.FriendlyName)"
                }
            }
            
            # Check if it's a CSV by looking at file system type or path
            $isCSV = $false
            $fileSystemType = ""
            $csvPath = ""
            
            if ($volume) {
                $isCSV = $volume.FileSystemType -eq 'CSVFS' -or $volume.FileSystemType -eq 'CSVFS_ReFS'
                $fileSystemType = $volume.FileSystemType
                if ($volume.Path -like '*Volume{*') {
                    $csvPath = $volume.Path
                }
            }
            
            $vdiskInfo = [PSCustomObject]@{
                FriendlyName = $vdisk.FriendlyName
                SizeGB = [math]::Round($vdisk.Size / 1GB, 2)
                SizeTB = Convert-BytesToTB -Bytes $vdisk.Size
                ResiliencySettingName = $vdisk.ResiliencySettingName
                NumberOfDataCopies = $vdisk.NumberOfDataCopies
                NumberOfColumns = $vdisk.NumberOfColumns
                PhysicalDiskRedundancy = $vdisk.PhysicalDiskRedundancy
                ProvisioningType = $vdisk.ProvisioningType
                HealthStatus = $vdisk.HealthStatus
                OperationalStatus = $vdisk.OperationalStatus
                IsCSV = $isCSV
                FileSystemType = $fileSystemType
                CSVPath = $csvPath
                FootprintOnPoolGB = [math]::Round($vdisk.FootprintOnPool / 1GB, 2)
                AllocatedSizeGB = [math]::Round($vdisk.AllocatedSize / 1GB, 2)
            }
            $virtualDiskData += $vdiskInfo
        }
        
        # Group by friendly name and filter CSVs
        $csvDisks = $virtualDiskData | Where-Object { $_.IsCSV -eq $true -or $_.FileSystemType -like '*CSV*' }
        $groupedByName = $virtualDiskData | Group-Object -Property FriendlyName
        
        return @{
            AllVirtualDisks = $virtualDiskData
            CSVDisks = $csvDisks
            GroupedByName = $groupedByName
        }
    }
    catch {
        Write-Error "Failed to gather virtual disk information: $($_.Exception.Message)"
        return $null
    }
}

function Export-Results {
    param(
        [object]$PhysicalDiskData,
        [object]$VirtualDiskData,
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    # Export physical disk data
    $physicalDiskData.AllDisks | Export-Csv -Path "$Path\PhysicalDisks-$timestamp.csv" -NoTypeInformation
    Write-Host "Physical disk data exported to: $Path\PhysicalDisks-$timestamp.csv" -ForegroundColor Yellow
    
    # Export virtual disk data
    $virtualDiskData.AllVirtualDisks | Export-Csv -Path "$Path\VirtualDisks-$timestamp.csv" -NoTypeInformation
    Write-Host "Virtual disk data exported to: $Path\VirtualDisks-$timestamp.csv" -ForegroundColor Yellow
    
    # Export CSV-specific data
    if ($virtualDiskData.CSVDisks.Count -gt 0) {
        $virtualDiskData.CSVDisks | Export-Csv -Path "$Path\CSVDisks-$timestamp.csv" -NoTypeInformation
        Write-Host "CSV disk data exported to: $Path\CSVDisks-$timestamp.csv" -ForegroundColor Yellow
    }
}

function Display-Results {
    param(
        [object]$PhysicalDiskData,
        [object]$VirtualDiskData,
        [string]$Format
    )
    
    # Get cluster name
    $clusterName = "Unknown"
    try {
        $cluster = Get-Cluster -ErrorAction SilentlyContinue
        if ($cluster) {
            $clusterName = $cluster.Name
        }
    }
    catch {
        Write-Warning "Could not retrieve cluster name: $($_.Exception.Message)"
    }
    
    $headerLine = "=" * 80
    Write-Host "`n$headerLine" -ForegroundColor Cyan
    Write-Host "AZURE LOCAL CLUSTER STORAGE INFORMATION" -ForegroundColor Cyan
    Write-Host "Cluster: $clusterName" -ForegroundColor Cyan
    Write-Host "$headerLine" -ForegroundColor Cyan
    
    # Display Physical Disk Information grouped by host
    Write-Host "`nPHYSICAL DISKS BY HOST:" -ForegroundColor Yellow
    $separatorLine = "-" * 40
    Write-Host "$separatorLine" -ForegroundColor Yellow
    
    # Sort host groups by name
    $sortedHostGroups = $PhysicalDiskData.GroupedByHost | Sort-Object Name
    
    foreach ($hostGroup in $sortedHostGroups) {
        Write-Host "`nHost: $($hostGroup.Name)" -ForegroundColor Green
        Write-Host "Disk Count: $($hostGroup.Count)" -ForegroundColor Green
        
        # Sort disks by FriendlyName within each host
        $hostDisks = $hostGroup.Group | Sort-Object FriendlyName | Select-Object UniqueID, FriendlyName, Model, PhysicalLocation, DeviceId, LogicalSectorSize, PhysicalSectorSize, SizeTB, MediaType, HealthStatus
        
        switch ($Format) {
            'Table' { $hostDisks | Format-Table -AutoSize }
            'List' { $hostDisks | Format-List }
            'CSV' { $hostDisks | ConvertTo-Csv -NoTypeInformation }
        }
    }
    
    # Display Virtual Disk Information (CSV focus)
    Write-Host "`nVIRTUAL DISKS (CLUSTER SHARED VOLUMES):" -ForegroundColor Yellow
    $csvSeparatorLine = "-" * 50
    Write-Host "$csvSeparatorLine" -ForegroundColor Yellow
    
    if ($VirtualDiskData.CSVDisks.Count -gt 0) {
        # Sort CSV disks by FriendlyName
        $csvDisks = $VirtualDiskData.CSVDisks | Sort-Object FriendlyName | Select-Object FriendlyName, SizeTB, ResiliencySettingName, NumberOfDataCopies, NumberOfColumns, ProvisioningType, HealthStatus, FileSystemType
        
        switch ($Format) {
            'Table' { $csvDisks | Format-Table -AutoSize }
            'List' { $csvDisks | Format-List }
            'CSV' { $csvDisks | ConvertTo-Csv -NoTypeInformation }
        }
    }
    else {
        Write-Host "No CSV disks found." -ForegroundColor Red
    }
    
    # Display ALL Virtual Disks grouped by name
    Write-Host "`nALL VIRTUAL DISKS BY FRIENDLY NAME:" -ForegroundColor Yellow
    $allVdiskSeparatorLine = "-" * 45
    Write-Host "$allVdiskSeparatorLine" -ForegroundColor Yellow
    
    # Sort virtual disk groups by name
    $sortedNameGroups = $VirtualDiskData.GroupedByName | Sort-Object Name
    
    foreach ($nameGroup in $sortedNameGroups) {
        Write-Host "`nVirtual Disk: $($nameGroup.Name)" -ForegroundColor Green
        
        $vdiskDetails = $nameGroup.Group | Select-Object SizeTB, ResiliencySettingName, NumberOfDataCopies, ProvisioningType, HealthStatus, IsCSV, FileSystemType
        
        switch ($Format) {
            'Table' { $vdiskDetails | Format-Table -AutoSize }
            'List' { $vdiskDetails | Format-List }
            'CSV' { $vdiskDetails | ConvertTo-Csv -NoTypeInformation }
        }
    }
    
    # Summary
    Write-Host "`nSUMMARY:" -ForegroundColor Yellow
    $summaryLine = "-" * 15
    Write-Host "$summaryLine" -ForegroundColor Yellow
    Write-Host "Total Physical Disks: $($PhysicalDiskData.AllDisks.Count)" -ForegroundColor White
    Write-Host "Total Virtual Disks: $($VirtualDiskData.AllVirtualDisks.Count)" -ForegroundColor White
    Write-Host "CSV Disks: $($VirtualDiskData.CSVDisks.Count)" -ForegroundColor White
    Write-Host "Unique Hosts: $($PhysicalDiskData.GroupedByHost.Count)" -ForegroundColor White
    
    $totalPhysicalTB = ($PhysicalDiskData.AllDisks | Measure-Object -Property SizeTB -Sum).Sum
    $totalVirtualTB = ($VirtualDiskData.AllVirtualDisks | Measure-Object -Property SizeTB -Sum).Sum
    
    Write-Host "Total Physical Storage: $([math]::Round($totalPhysicalTB, 2)) TB" -ForegroundColor White
    Write-Host "Total Virtual Storage: $([math]::Round($totalVirtualTB, 2)) TB" -ForegroundColor White
}

# Main execution
try {
    Write-Host "Starting Azure Local storage information gathering..." -ForegroundColor Cyan
    
    # Gather physical disk information
    $physicalDiskData = Get-PhysicalDiskInfo
    if (-not $physicalDiskData) {
        throw "Failed to gather physical disk information"
    }
    
    # Gather virtual disk information
    $virtualDiskData = Get-VirtualDiskInfo -IncludeVolumes:$IncludeVolumeInfo
    if (-not $virtualDiskData) {
        throw "Failed to gather virtual disk information"
    }
    
    # Display results
    Display-Results -PhysicalDiskData $physicalDiskData -VirtualDiskData $virtualDiskData -Format $OutputFormat
    
    # Export if requested
    if ($ExportPath) {
        Export-Results -PhysicalDiskData $physicalDiskData -VirtualDiskData $virtualDiskData -Path $ExportPath
    }
    
    Write-Host "`nStorage information gathering completed successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
