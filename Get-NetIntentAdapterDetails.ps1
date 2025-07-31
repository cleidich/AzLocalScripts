<#
.SYNOPSIS
    Retrieves network adapter details for each network intent and their associated IPv4 addresses.

.DESCRIPTION
    This script uses Get-NetIntent to gather all network intents on the host, then for each intent
    it extracts the associated network adapters from the NetAdapterNameCsv property and retrieves
    their IPv4 addresses, names, descriptions, and associated intent names.
    
    The script outputs detailed information about each adapter including:
    - Intent Name
    - Adapter Name
    - Adapter Description
    - IPv4 Address(es)
    - MAC Address
    - Driver Name, Version, and Date

.PARAMETER OutputFile
    The path to the output text file. Default is .\IntentAdapterDetails.txt

.PARAMETER ExcludeDisconnected
    Exclude adapters that are disconnected or don't have IP addresses assigned.
    Default is $false (show all adapters including disconnected ones).

.EXAMPLE
    .\Get-NetIntentAdapterDetails.ps1
    Exports adapter details to .\IntentAdapterDetails.txt

.EXAMPLE
    .\Get-NetIntentAdapterDetails.ps1 -OutputFile "C:\Reports\AdapterDetails.txt" -ExcludeDisconnected
    Exports adapter details excluding disconnected ones to the specified file path

.NOTES
    This script is designed to be run on Azure Local cluster nodes or systems
    with the NetworkController PowerShell module available.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputFile = ".\IntentAdapterDetails.txt",
    
    [Parameter(Mandatory = $false)]
    [switch]$ExcludeDisconnected
)

function Get-AdapterIPv4Details {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AdapterName
    )
    
    try {
        # Get the network adapter
        $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
        
        if (-not $adapter) {
            return @{
                Name = $AdapterName
                Description = "[ADAPTER NOT FOUND]"
                IPv4Addresses = @()
                Status = "NotFound"
                MacAddress = "[NOT AVAILABLE]"
                DriverName = "[NOT AVAILABLE]"
                DriverVersion = "[NOT AVAILABLE]"
                DriverDate = "[NOT AVAILABLE]"
            }
        }
        
        # Get IPv4 addresses for this adapter
        $ipAddresses = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                      Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -ne "WellKnown" } |
                      Select-Object -ExpandProperty IPAddress
        
        # Get driver information directly from adapter properties
        $driverName = if ($adapter.DriverName) { $adapter.DriverName } else { "[UNKNOWN]" }
        $driverVersion = if ($adapter.DriverVersion) { $adapter.DriverVersion } else { "[UNKNOWN]" }
        $driverDate = "[UNKNOWN]"
        
        # Handle DriverDate carefully as it might not be a DateTime object
        try {
            if ($adapter.DriverDate) {
                if ($adapter.DriverDate -is [DateTime]) {
                    $driverDate = $adapter.DriverDate.ToString("yyyy-MM-dd")
                } else {
                    $driverDate = $adapter.DriverDate.ToString()
                }
            }
        }
        catch {
            $driverDate = "[ERROR PARSING DATE]"
        }
        
        return @{
            Name = $adapter.Name
            Description = $adapter.InterfaceDescription
            IPv4Addresses = $ipAddresses
            Status = $adapter.Status
            InterfaceIndex = $adapter.InterfaceIndex
            MacAddress = $adapter.MacAddress
            DriverName = $driverName
            DriverVersion = $driverVersion
            DriverDate = $driverDate
        }
    }
    catch {
        return @{
            Name = $AdapterName
            Description = "[ERROR RETRIEVING DETAILS]"
            IPv4Addresses = @()
            Status = "Error"
            Error = $_.Exception.Message
            MacAddress = "[ERROR]"
            DriverName = "[ERROR]"
            DriverVersion = "[ERROR]"
            DriverDate = "[ERROR]"
        }
    }
}

function Write-AdapterDetails {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.StreamWriter]$Writer,
        
        [Parameter(Mandatory = $true)]
        [string]$IntentName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AdapterDetails,
        
        [Parameter(Mandatory = $false)]
        [int]$AdapterNumber
    )
    
    $Writer.WriteLine("  Adapter #$AdapterNumber")
    $Writer.WriteLine("  " + ("-" * 30))
    $Writer.WriteLine("    Name: $($AdapterDetails.Name)")
    $Writer.WriteLine("    Description: $($AdapterDetails.Description)")
    $Writer.WriteLine("    Status: $($AdapterDetails.Status)")
    $Writer.WriteLine("    MAC Address: $($AdapterDetails.MacAddress)")
    $Writer.WriteLine("    Driver Name: $($AdapterDetails.DriverName)")
    $Writer.WriteLine("    Driver Version: $($AdapterDetails.DriverVersion)")
    $Writer.WriteLine("    Driver Date: $($AdapterDetails.DriverDate)")
    
    if ($AdapterDetails.IPv4Addresses -and $AdapterDetails.IPv4Addresses.Count -gt 0) {
        $Writer.WriteLine("    IPv4 Address(es):")
        foreach ($ip in $AdapterDetails.IPv4Addresses) {
            $Writer.WriteLine("      - $ip")
        }
    }
    else {
        $Writer.WriteLine("    IPv4 Address(es): [NONE ASSIGNED]")
    }
    
    if ($AdapterDetails.Error) {
        $Writer.WriteLine("    Error: $($AdapterDetails.Error)")
    }
    
    $Writer.WriteLine("")
}

# Main script execution
try {
    Write-Host "Starting network intent adapter analysis..." -ForegroundColor Green
    
    # Get all network intents
    Write-Host "Retrieving network intents using Get-NetIntent..." -ForegroundColor Yellow
    $netIntents = Get-NetIntent
    
    if (-not $netIntents) {
        Write-Warning "No network intents found on this system."
        return
    }
    
    Write-Host "Found $($netIntents.Count) network intent(s). Analyzing adapters..." -ForegroundColor Yellow
    
    # Create output directory if it doesn't exist
    $outputDir = Split-Path -Path $OutputFile -Parent
    if ($outputDir -and -not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # Create the output file
    $writer = [System.IO.StreamWriter]::new($OutputFile, $false, [System.Text.Encoding]::UTF8)
    
    try {
        # Get cluster information
        try {
            $clusterInfo = Get-Cluster -ErrorAction SilentlyContinue
            $clusterName = if ($clusterInfo) { $clusterInfo.Name } else { "[NOT CLUSTERED]" }
        }
        catch {
            $clusterName = "[CLUSTER INFO UNAVAILABLE]"
        }
        
        # Write header
        $writer.WriteLine("=" * 80)
        $writer.WriteLine("NETWORK INTENT ADAPTER DETAILS REPORT")
        $writer.WriteLine("Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $writer.WriteLine("Host: $env:COMPUTERNAME")
        $writer.WriteLine("Cluster: $clusterName")
        $writer.WriteLine("Total Intents Found: $($netIntents.Count)")
        $writer.WriteLine("Exclude Disconnected: $ExcludeDisconnected")
        $writer.WriteLine("=" * 80)
        $writer.WriteLine("")
        
        $totalAdaptersProcessed = 0
        $adaptersWithIP = 0
        
        # Process each intent
        for ($i = 0; $i -lt $netIntents.Count; $i++) {
            $intent = $netIntents[$i]
            $intentName = if ($intent.IntentName) { $intent.IntentName } else { "Intent_$($i + 1)" }
            
            $writer.WriteLine("INTENT: $intentName")
            $writer.WriteLine("-" * 50)
            
            # Check if NetAdapterNameCsv property exists and has value
            if ($intent.NetAdapterNameCsv -and -not [string]::IsNullOrWhiteSpace($intent.NetAdapterNameCsv)) {
                # Split the adapter names by # delimiter
                $adapterNames = $intent.NetAdapterNameCsv -split '#' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                
                if ($adapterNames.Count -gt 0) {
                    $writer.WriteLine("Associated Adapters: $($adapterNames.Count)")
                    $writer.WriteLine("")
                    
                    for ($j = 0; $j -lt $adapterNames.Count; $j++) {
                        $adapterName = $adapterNames[$j].Trim()
                        $totalAdaptersProcessed++
                        
                        # Get adapter details
                        $adapterDetails = Get-AdapterIPv4Details -AdapterName $adapterName
                        
                        # Check if we should include this adapter
                        $shouldInclude = -not $ExcludeDisconnected -or 
                                        ($adapterDetails.IPv4Addresses -and $adapterDetails.IPv4Addresses.Count -gt 0)
                        
                        if ($shouldInclude) {
                            if ($adapterDetails.IPv4Addresses -and $adapterDetails.IPv4Addresses.Count -gt 0) {
                                $adaptersWithIP++
                            }
                            
                            Write-AdapterDetails -Writer $writer -IntentName $intentName -AdapterDetails $adapterDetails -AdapterNumber ($j + 1)
                        }
                    }
                }
                else {
                    $writer.WriteLine("Associated Adapters: [EMPTY ADAPTER LIST]")
                    $writer.WriteLine("")
                }
            }
            else {
                $writer.WriteLine("Associated Adapters: [NO NETADAPTERNAMECSV PROPERTY OR EMPTY]")
                $writer.WriteLine("")
            }
            
            # Add separator between intents (except for the last one)
            if ($i -lt $netIntents.Count - 1) {
                $writer.WriteLine("=" * 80)
                $writer.WriteLine("")
            }
        }
        
        # Write summary
        $writer.WriteLine("")
        $writer.WriteLine("=" * 80)
        $writer.WriteLine("SUMMARY")
        $writer.WriteLine("-" * 20)
        $writer.WriteLine("Total Intents Processed: $($netIntents.Count)")
        $writer.WriteLine("Total Adapters Processed: $totalAdaptersProcessed")
        $writer.WriteLine("Adapters with IPv4 Addresses: $adaptersWithIP")
        $writer.WriteLine("Adapters without IPv4 Addresses: $($totalAdaptersProcessed - $adaptersWithIP)")
        $writer.WriteLine("=" * 80)
        $writer.WriteLine("END OF REPORT")
        $writer.WriteLine("=" * 80)
        
        Write-Host "Network intent adapter analysis completed successfully!" -ForegroundColor Green
        Write-Host "Report exported to: $OutputFile" -ForegroundColor Green
        Write-Host "Total adapters processed: $totalAdaptersProcessed" -ForegroundColor Green
        Write-Host "Adapters with IPv4 addresses: $adaptersWithIP" -ForegroundColor Green
    }
    finally {
        $writer.Close()
        $writer.Dispose()
    }
}
catch {
    Write-Error "An error occurred while processing network intent adapters: $($_.Exception.Message)"
    Write-Error "Stack Trace: $($_.ScriptStackTrace)"
    
    # Clean up file handle if it exists
    if ($writer) {
        $writer.Close()
        $writer.Dispose()
    }
    
    exit 1
}
