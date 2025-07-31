# Azure Local Discovery Scripts

This repository contains helpful PowerShell scripts designed to gather information about Azure Local clusters and their network configurations. These scripts are intended for diagnostic and discovery purposes on Azure Local cluster nodes.

## ⚠️ Disclaimer

**USE AT YOUR OWN RISK**: These scripts are provided as-is without warranty. Always test in a non-production environment first. The authors are not responsible for any damage or issues that may arise from using these scripts.

## Prerequisites

- PowerShell 5.1 or later
- NetworkController PowerShell module (available on Azure Local cluster nodes)
- Appropriate permissions to query network configurations
- Scripts should be run on Azure Local cluster nodes or systems with access to the required PowerShell modules

## Scripts

### Get-AllNetIntentDetails.ps1

**Purpose**: Retrieves comprehensive network intent details from the local host and exports them to a text file.

**What it does**:
- Uses `Get-NetIntent` to gather all network intents on the host
- Exports intent properties with expanded details for specific override properties
- Provides detailed analysis of:
  - AdapterAdvancedParametersOverride
  - RssConfigOverride
  - QosPolicyOverride
  - SwitchConfigOverride
  - IPOverride
  - NetAdapterCommonProperties

**Usage**:
```powershell
# Export to default location (.\IntentData.txt)
.\Get-AllNetIntentDetails.ps1

# Export to custom location
.\Get-AllNetIntentDetails.ps1 -OutputFile "C:\Reports\NetworkIntents.txt"
```

### Get-NetIntentAdapterDetails.ps1

**Purpose**: Retrieves detailed network adapter information for each network intent and their associated IPv4 addresses.

**What it does**:
- Extracts network adapters associated with each network intent
- Retrieves comprehensive adapter details including:
  - Intent Name and Adapter Name
  - Adapter Description and Status
  - IPv4 Address assignments
  - MAC Address
  - Driver Name, Version, and Date
- Provides filtering options for connected/disconnected adapters

**Usage**:
```powershell
# Export all adapters to default location (.\IntentAdapterDetails.txt)
.\Get-NetIntentAdapterDetails.ps1

# Export only connected adapters with IP addresses to custom location
.\Get-NetIntentAdapterDetails.ps1 -OutputFile "C:\Reports\AdapterDetails.txt" -ExcludeDisconnected
```

## Output

All scripts generate detailed text-based reports with:
- Timestamped headers
- Host and cluster information
- Organized, human-readable format
- Summary statistics
- Error handling and reporting

## Best Practices

1. **Run locally**: Execute these scripts directly on Azure Local cluster nodes for best results
2. **Check permissions**: Ensure you have appropriate rights to query network configurations
3. **Review output**: Always review the generated reports for any error messages or missing data
4. **Archive reports**: Keep reports for historical comparison and troubleshooting
5. **Test first**: Run scripts in a test environment before using in production

## Support

These scripts are community-provided tools. For Azure Local support, please refer to official Microsoft documentation and support channels.

## Contributing

Feel free to submit improvements, bug fixes, or additional discovery scripts that follow the same patterns and coding standards established in this repository.
