#Requires -Version 3.0
#requires -Modules @{ModuleName="AzureRM";ModuleVersion=6.1}
[cmdletbinding(DefaultParametersetName="Local")]
param(
[Parameter(ParameterSetName='HostInput',Mandatory = $false)][string]$AzureRegion = "westeurope",
[Parameter(ParameterSetName='HostInput',Mandatory = $false)]
[ValidateLength(3,11)][string]$Company = "Sentia",
[Parameter(ParameterSetName='HostInput',Mandatory = $true)]
[ValidateSet("Dev","Accept","Test","Prod")][string]$Environment,
[Parameter(ParameterSetName='HostInput',Mandatory = $false)]
[ValidateSet("Standard_LRS","Standard_GRS","Standard_ZRS")][string]$SkuName = "Standard_LRS",
[Parameter(ParameterSetName='HostInput',Mandatory = $false)]
[string]$SupernetCIDR = "172.16.0.0/12",
[Parameter(ParameterSetName='HostInput',Mandatory = $true)]
[ValidateRange(1,32)][int]$SubnetCount,
[Parameter(ParameterSetName='Local',Mandatory = $true)]
[ValidateScript({ Test-Path -Path $_ -PathType Leaf })][string]$TemplatePath,
[Parameter(ParameterSetName='Local',Mandatory = $false)]
[ValidateScript({ Test-Path -Path $_ -PathType Leaf })][string]$TemplateParameterFile,
[Parameter(ParameterSetName='Remote',Mandatory = $true)][string]$TemplateURI,
[Parameter(ParameterSetName='Remote',Mandatory = $false)][string]$TemplateParameterURI,
[Parameter(ParameterSetName='Local',Mandatory = $true)]
[Parameter(ParameterSetName='Remote',Mandatory = $true)]
[ValidateSet("Incremental","Complete")][string]$DeployMode,
[Parameter(ParameterSetName='Local',Mandatory = $true)]
[Parameter(ParameterSetName='Remote',Mandatory = $true)]
[Parameter(Mandatory = $false)][string]$TemplateVersion
)

process{
#if selected subscription is enabled
if ([bool]$AzureSubscription.State){
	#$AzureRoleAssignments = Get-AzureRMRoleAssignment 
	#process depending on used parameterset
	switch ($PsCmdlet.ParameterSetName){
		"HostInput" {
			$ResourceGroupName = "$($Company)_$($Environment)"
			$Tags = @{"Environment"=$Environment; "Company"=$Company; "Application"="Intake"}
			if (!(Get-AzureRMResourceGroup $ResourceGroupName)){
				$ResourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $AzureRegion -Tag $Tags
				}
			Out-Put "creation of resourcegroup $($ResourceGroup.ProvisioningState):$($nl)$($ResourceGroup)"
			if ($ResourceGroup.ProvisioningState -eq "Succeeded"){
				#register allowed policy resources
				$ResourceProviders = @("Microsoft.Compute","Microsoft.Network","Microsoft.Storage")
				foreach ($Provider in $ResourceProviders){ Register-AzureRmResourceProvider -ProviderNamespace $Provider }
				#create storage account
				#concatenate company prefix with guid with 24 character limit
				$StorageAccountName = "$($Company)$([guid]::NewGuid())".ToLower().Replace("-","").Substring(0,24)
				$StorageAccount = New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -Tags $Tags -Location $AzureRegion -Kind Storagev2 -SkuName $SkuName
				#set encryption using Microsoft Storage
				Set-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccount.StorageAccountName -StorageEncryption
				Out-Put "creation of storage $($StorageAccount.ProvisioningState):$($nl)$($StorageAccount)"
				#create network resource
				$NetworkSecurityGroup = New-AzureRmNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $AzureRegion -Name "$($Company)-NSG" -Tag $Tags
				Out-Put "creation of securitygroup $($NetworkSecurityGroup.ProvisioningState):$($nl)$($NetworkSecurityGroup)"
				if ($NetworkSecurityGroup.ProvisioningState -eq "Succeeded"){
					$NewAzureLAN = New-AzureRmVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $AzureRegion -Name "$($Company)_VLAN" -AddressPrefix $SuperNetCIDR -Tag $Tags
					Out-Put "creation of virtual network $($NewAzureLAN.ProvisioningState):$($nl)$($NewAzureLAN)"
					if ($NewAzureLAN.ProvisioningState -eq "Succeeded"){
						For ($i=0; $i -lt $SubnetCount; $i++) {
							$SubnetName = "Subnet$($i)"
							$SubnetAddressPrefix = Get-SubnetAddressPrefix -SupernetCIDR $SupernetCIDR -Counter $i
							Add-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetAddressPrefix -VirtualNetwork $NewAzureLAN -NetworkSecurityGroup $NetworkSecurityGroup
							}
						Set-AzureRmVirtualNetwork -VirtualNetwork $NewAzureLAN
						}
					}
				#set policy definition?
				}
			}#HostInput
		"Local"{
			if(-not (Test-Path $TemplateParameterFile)) {
				$DeployProps = @{
					Name = "$($Company)_$($Environment)"
					ResourceGroupName = $ResourceGroupName
					TemplateFile = $TemplatePath
					storageAccountType = $storageSKU
					TemplateVersion = $TemplateVersion
					Mode = $DeployMode
					}
				}
			else { $DeployProps.Add("TemplateParameterFile", $TemplateParameterFile)}
			#Test-AzureRmResourceGroupDeployment
			$ResourceDeployment = New-AzureRmResourceGroupDeployment @DeployProps
		}#Local
		"Remote"{
			if(-not (Test-Path $TemplateParameterURI)) {
				$DeployProps = @{
					Name = "$($Company)_$($Environment)"
					ResourceGroupName = $ResourceGroupName
					TemplateURI = $TemplateURI
					storageAccountType = $storageSKU
					TemplateVersion = $TemplateVersion
					Mode = $DeployMode
					}
				}
			else { $DeployProps.Add("TemplateParameterURI", $TemplateParameterURI)}
			#Test-AzureRmResourceGroupDeployment
			$ResourceDeployment = New-AzureRmResourceGroupDeployment @DeployProp
			}#Remote
		}#switch
	}#if
else { 
	Write-Error "No active subscription $($SubscriptionName) found $($nl)$($AzureSubscription)"
	exit
	}
}

begin{
$nl = [environment]::NewLine
#create unique log file on central file share
$script:OutLog = Join-Path "\\syslogserver\azure\logs\" "$($env:computername)_$($env:username)_$(Get-Date -Format "dd-MM-yyyy_hh-mm-ss")"
#Azure account
#Set-AzureRMContext
#$Credential = Get-Credential
Connect-AzureRmAccount #-ServicePrincipal $SPN
$AzureSubscription = Get-AzureRmSubscription | Out-GridView -Title "Select Azure subscription" -OutputMode Single
#$AzureSubscription = Select-AzureRmSubscription -SubscriptionName $SubscriptionName -TenantID $AzureAccount.TenantID #-SubscriptionId $SubscriptionID
Set-AzureRmContext -SubscriptionId $AzureSubscription.Id

Function Out-Put ($InString){
#display incoming message and append to log file
$InString | Tee-Object -FilePath $script:OutLog -Append
}

Function Get-SubnetAddressPrefix {
param(
[string]$SupernetCIDR,
[int]$Counter
)
$SupernetAddressPrefix = ($SupernetCIDR -split "/")[0] #remove CIDR notation
$SupernetIPRange = ($SupernetAddressPrefix -split "\.") #divide IP address into array of decimals
[int]$SupernetIPRange[2] += $Counter #add counter value to C-class subnet decimal
$SubnetAddressPrefix = $SupernetIPRange -join "." #rejoin decimals
return "$($SubnetAddressPrefix)/24" #return C-class network address in CIDR notation
}
}

end{
Disconnect-AzureRmAccount
}