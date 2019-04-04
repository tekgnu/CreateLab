<# CREATELAB 
	.SYNOPSIS
	This powershell script is used to build out the Azure Architecture elements needed to support testing functionality and creating infrastructure for testing
		Client environments in a Hub / Spoke model.

	.DESCRIPTION
	Full environment meant to be built and deleted as needed.  This will align tightly with an associated architecture as needed.  Currently does not support command line arguments.
		Requires:
			Powershell 5.1+ 
			AZ 1.0.0+

	.EXAMPLE
	./CreateLab.ps1

	.LINK
	https://github.com/tekgnu/CreateLab
#>
# Parameter Declarations

# GLOBAL DECLARATIONS
#		Configurations that will impact the scripts behavior
	# Deploy Region represents the Azure region as well as teh two digit code used for the naming convention
	# Defined by DeployRegion ID.
	$deployRegionID = "eastus"

	# Admin Username can be pre-assigned, but passwords are created at runtime
	$adminUsername 

	# Determines is the Resource Group exists, if all of the missing resources should be created, or not
	$appendResources = True

# CONFIGURATION SPECIFIC DECLARATIONS 
#		Configurations that will impact the architecture

	# Network configurations for the HubVNet and Subnets
	$hubVnetwork = "10.0.5.0/24"
	$hubGatewaySubnet = "10.0.5.0/26"
	$hubManagementSubnet = "10.0.5.64/27"


	# Network configurations for the TestVNet and Subnets
	$spoTestVnetwork = "10.0.6.0/24"
	$spoTestSubnet = "10.0.6.0/26"


	# Network configurations for the ClientVNet
	$spoClientVnetwork = "10.0.7.0/24"

	# Default Client Configurations
	#	This will create a client subnet, with the 3 Digit Opportunity ID and Subnet see below for Naming convention
	$spoClient_Network = ("doe", "10.0.7.0/27"), ("coo", "10.0.7.32/27"), ("edj", "10.0.7.64/27"), ("Max", "10.0.7.96/27")



# Variables Declaration
$deployRegion = @{eastus = "eu"; eastus2 = "e2"; northcentralus = "nc"; canadacentral = "cc"; canadaeast = "ce"; centralus = "cu"; southcentral = "sc"; westus = "wu"; westus2 = "w2";  westcentralus = "wc"; usgovarizona = "ga"; usgovtexas = "gt"; usgovvirginia = "gv"; usdodcentral = "zc"; usdodeast = "ze" }

<# Shortform variable declaration - sets naming convention
	Used for a 15 character naming convention standard of the form:
		2 Digit Opportunity (client or internal cl/mp)
		3 Digit Environment (prd, tst, dev)
		2 Digit location (above)
		3 Digit product or service (below - by Azure service)
		3 Digit role (free form text)
		2 Digit number

#>
$oppID = @{Client = "cl"; Internal = "mp"}
$environment = @("prd", "tst", "dev", "qlt") 

$deployAsset = @{
	networkSecurityGroup	= "nsg";
	compute		 			= "cpt";
	resourceGroup			= "rgp";
	loadBalancer			= "nlb";
	networkInterface		= "nic";
	storageAccount			= "sto";
	blob					= "blo";
	subnet					= "sub";
	publicIP				= "pip";
	vnet					= "vnt";
	vnetPeer				= "vnp"
}

$clientResourcePrefix = $oppID['Client'] + $environment[1] + $deployRegion[($deployRegionID)]
$internalResourcePrefix = $oppID['Internal'] + $environment[1] + $deployRegion[($deployRegionID)]

#	REUSABLE FUNCTIONS
#		This is just some functions added to create consistency
<#
.Synopsis
   Checks if a Resource Group with the provided Location and Name exists. 
   Returns true if the Resource Group with that name exists in that AZ region
    else false
#>
function testIfRGExists {
 param( [string]$Location, [String]$Name )
 return ((Get-AzResourceGroup -Location $Location).ResourceGroupName -eq $Name)
}

<#
.Synopsis
	Function testIfResourceExists ResourceGroupName ResourceName
   Checks if a Resource with the provided Name and Location exists. 
   Returns true if the Resource Group with that name exists in that AZ region
    else false
#>
function testIfResourceExists {
 param( [string]$ResourceGroupName, [String]$ResourceName )
 return ((Get-AzResource -ResourceGroupName $ResourceGroupName).Name -eq $ResourceName)
}

#	BEGINNING SCRIPT

# Filling in the data that was not or should not be added before RUNTIME
if ($NULL -eq $adminUsername)
{
	$adminUsername = Read-Host "Enter an Admin username."
}
$admin_pwd_secure_string = Read-Host "Enter a Password for the Administrator" -AsSecureString



<# $deviceName =  $internalResourcePrefix + $deployAsset["compute"] + "web" + "01"
write-host "Servername is $devicename"
#>

if ($null -eq $adminUsername)
{
	$adminUsername = Read-Host "Enter a default administrator username: "
}
Write-host "The Default Administrator Username will be: $adminUsername"

$pwd_secure_string = Read-Host "Enter a Password for the Default Admin" -AsSecureString


<#
	Execute script - will capture each section of activity.
		Please ensure alignment with the defined architecture!
#>
Connect-AzAccount
<#
	Creating Hub and System infrastructure
#>

$hubRGName = $internalResourcePrefix + $deployAsset["resourceGroup"] + "sys" + "01"

if (testIfRGExists $deployRegion[($deployRegionID)] $hubRGName)
{
	Write-Host "Resource Group $hubRGName Already Exists."
 	if ($appendResources -eq $FALSE) 
 	{
 		Write-Host "Cancelling resource creation: ERROR Existing Resource Group $hubRGName"
 		exit 1
 	}	
}
Write-host "Creating the hub Resource Group - $hubRGName"
New-AzResourceGroup -Location $deployRegion[($deployRegionID)] -Name $hubRGName

	<#
		Creating Hub VNET, Gateway, and Management Subnets
	#>
	$hubVnetworkName 				= $internalResourcePrefix + $deployAsset["vnet"] + "hub" + "01"
	$hubManagementSubnetName 	= $internalResourcePrefix + $deployAsset["subnet"] + "hub" + "01"
	$hubGatewaySubnetName 		= $internalResourcePrefix + $deployAsset["subnet"] + "gwy" + "01"

	#	Create Hub Management Subnet
	if (testIfResourceExists $deployRegion[($deployRegionID)] $hubManagementSubnetName)
	{
		Write-Host "Hub Subnet $hubManagementSubnetName Already Exists."
		if ($appendResources -eq $FALSE) 
 		{
			Write-Host "Cancelling resource creation: ERROR Existing Subnet $hubManagementSubnetName"
 			exit 1
		}
	}
	Write-host "Now creating the HUB Subnet $hubManagementSubnetName on Network $hubManagmentSubnet"
	$hubMGTSub = New-AzVirtualNetworkSubnetConfig -Name $hubManagementSubnetName -AddressPrefix $hubManagementSubnet

	<#  NEED TO UNDERSTAND HOW TO CREATE IN POWERSHELL
	#	Create Hub Gateway Subnet
	if (testIfResourceExists $deployRegion[($deployRegionID)] $hubGatewaySubnetName)
	{
		Write-Host "Hub Subnet $hubGatewaySubnetName Already Exists."
		if ($appendResources -eq $FALSE) 
 		{
			Write-Host "Cancelling resource creation: ERROR Existing Subnet $hubGatewaySubnetName"
 			exit 1
		}
	}
	Write-host "Now creating the HUB Subnet $hubGatewaySubnetName on Network $hubGatewaySubnet"
	$hubGWYSub = New-AzVirtualNetworkSubnetConfig -Name $hubGatewaySubnetName -AddressPrefix $hubGatewaySubnet
#>

#	Create Hub Management Virtual Network
if (testIfResourceExists $deployRegion[($deployRegionID)] $hubVnetworkName)
{
	Write-Host "Hub VNet $hubVnetworkName Already Exists."
	if ($appendResources -eq $FALSE) 
	 {
		Write-Host "Cancelling resource creation: ERROR Existing Vnet $hubVnetworkName"
		 exit 1
	}
}
Write-host "Now creating the HUB VNet $hubVnetworkName on Network $hubVnetwork"
New-AzVirtualNetwork -Name $hubVnetworkName -ResourceGroupName $hubRGName -Location $deployRegion[($deployRegionID)] -AddressPrefix $hubVnetwork -Subnet $hubMGTSub


