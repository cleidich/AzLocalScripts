<#
.SYNOPSIS
    Retrieves all network intent details from the local host and exports them to a text file.

.DESCRIPTION
    This script uses Get-NetIntent to gather all network intents on the host and exports
    the intent properties along with expanded details for specific override properties
    to an organized text file format.
    
    The script expands the following properties for detailed analysis:
    - AdapterAdvancedParametersOverride
    - RssConfigOverride
    - QosPolicyOverride
    - SwitchConfigOverride
    - IPOverride
    - NetAdapterCommonProperties

.PARAMETER OutputFile
    The path to the output text file. Default is .\IntentData.txt

.EXAMPLE
    .\Get-AllNetIntentDetails.ps1
    Exports intent data to .\IntentData.txt

.EXAMPLE
    .\Get-AllNetIntentDetails.ps1 -OutputFile "C:\Reports\NetworkIntents.txt"
    Exports intent data to the specified file path

.NOTES
    This script is designed to be run on Azure Local cluster nodes or systems
    with the NetworkController PowerShell module available.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputFile = ".\IntentData.txt"
)

function Write-IntentProperty {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.StreamWriter]$Writer,
        
        [Parameter(Mandatory = $true)]
        [string]$PropertyName,
        
        [Parameter(Mandatory = $false)]
        $PropertyValue,
        
        [Parameter(Mandatory = $false)]
        [int]$IndentLevel = 0
    )
    
    $indent = "  " * $IndentLevel
    
    if ($null -eq $PropertyValue) {
        $Writer.WriteLine("$indent$PropertyName`: [NULL]")
    }
    elseif ($PropertyValue -is [string] -and [string]::IsNullOrWhiteSpace($PropertyValue)) {
        $Writer.WriteLine("$indent$PropertyName`: [EMPTY]")
    }
    else {
        $Writer.WriteLine("$indent$PropertyName`: $PropertyValue")
    }
}

function Write-ExpandedProperty {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.StreamWriter]$Writer,
        
        [Parameter(Mandatory = $true)]
        [string]$PropertyName,
        
        [Parameter(Mandatory = $false)]
        $PropertyValue
    )
    
    $Writer.WriteLine("  $PropertyName`:")
    
    if ($null -eq $PropertyValue) {
        $Writer.WriteLine("    [NULL]")
        return
    }
    
    if ($PropertyValue -is [array] -and $PropertyValue.Count -eq 0) {
        $Writer.WriteLine("    [EMPTY ARRAY]")
        return
    }
    
    if ($PropertyValue -is [array]) {
        for ($i = 0; $i -lt $PropertyValue.Count; $i++) {
            $Writer.WriteLine("    [$i]:")
            $item = $PropertyValue[$i]
            
            if ($null -ne $item) {
                $properties = $item | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                foreach ($prop in $properties) {
                    $value = $item.$prop
                    Write-IntentProperty -Writer $Writer -PropertyName $prop -PropertyValue $value -IndentLevel 3
                }
            }
            else {
                $Writer.WriteLine("      [NULL ITEM]")
            }
            
            if ($i -lt $PropertyValue.Count - 1) {
                $Writer.WriteLine("")
            }
        }
    }
    else {
        # Single object
        $properties = $PropertyValue | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        if ($properties) {
            foreach ($prop in $properties) {
                $value = $PropertyValue.$prop
                Write-IntentProperty -Writer $Writer -PropertyName $prop -PropertyValue $value -IndentLevel 2
            }
        }
        else {
            $Writer.WriteLine("    $PropertyValue")
        }
    }
}

# Main script execution
try {
    Write-Host "Starting network intent data collection..." -ForegroundColor Green
    
    # Get all network intents
    Write-Host "Retrieving network intents using Get-NetIntent..." -ForegroundColor Yellow
    $netIntents = Get-NetIntent
    
    if (-not $netIntents) {
        Write-Warning "No network intents found on this system."
        return
    }
    
    Write-Host "Found $($netIntents.Count) network intent(s). Writing to file: $OutputFile" -ForegroundColor Yellow
    
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
        $writer.WriteLine("NETWORK INTENT DETAILS REPORT")
        $writer.WriteLine("Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $writer.WriteLine("Host: $env:COMPUTERNAME")
        $writer.WriteLine("Cluster: $clusterName")
        $writer.WriteLine("Total Intents Found: $($netIntents.Count)")
        $writer.WriteLine("=" * 80)
        $writer.WriteLine("")
        
        # Properties to expand (as specified in requirements)
        $expandedProperties = @(
            "AdapterAdvancedParametersOverride",
            "RssConfigOverride", 
            "QosPolicyOverride",
            "SwitchConfigOverride",
            "IPOverride",
            "NetAdapterCommonProperties"
        )
        
        # Process each intent
        for ($i = 0; $i -lt $netIntents.Count; $i++) {
            $intent = $netIntents[$i]
            
            $writer.WriteLine("INTENT #$($i + 1)")
            $writer.WriteLine("-" * 40)
            
            # Get all properties of the intent
            $allProperties = $intent | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
            
            # Write basic properties first (excluding the ones we'll expand)
            $basicProperties = $allProperties | Where-Object { $_ -notin $expandedProperties }
            
            $writer.WriteLine("Basic Properties:")
            foreach ($propName in $basicProperties) {
                $value = $intent.$propName
                Write-IntentProperty -Writer $writer -PropertyName $propName -PropertyValue $value -IndentLevel 1
            }
            
            $writer.WriteLine("")
            $writer.WriteLine("Expanded Override Properties:")
            
            # Write expanded properties
            foreach ($expandedProp in $expandedProperties) {
                if ($expandedProp -in $allProperties) {
                    $value = $intent.$expandedProp
                    Write-ExpandedProperty -Writer $writer -PropertyName $expandedProp -PropertyValue $value
                    $writer.WriteLine("")
                }
                else {
                    $writer.WriteLine("  $expandedProp`: [PROPERTY NOT FOUND]")
                    $writer.WriteLine("")
                }
            }
            
            # Add separator between intents (except for the last one)
            if ($i -lt $netIntents.Count - 1) {
                $writer.WriteLine("=" * 80)
                $writer.WriteLine("")
            }
        }
        
        # Write footer
        $writer.WriteLine("")
        $writer.WriteLine("=" * 80)
        $writer.WriteLine("END OF REPORT")
        $writer.WriteLine("=" * 80)
        
        Write-Host "Network intent data successfully exported to: $OutputFile" -ForegroundColor Green
        Write-Host "Report contains details for $($netIntents.Count) network intent(s)." -ForegroundColor Green
    }
    finally {
        $writer.Close()
        $writer.Dispose()
    }
}
catch {
    Write-Error "An error occurred while processing network intents: $($_.Exception.Message)"
    Write-Error "Stack Trace: $($_.ScriptStackTrace)"
    
    # Clean up file handle if it exists
    if ($writer) {
        $writer.Close()
        $writer.Dispose()
    }
    
    exit 1
}