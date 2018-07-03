<#
Requires -Version 5.0
Requires -Module AzureRM 6.2.1
Requires -Module AzureAD 2.0.0.131
#>

Param(
    [string] [Parameter(Mandatory=$true)] $ResourceGroupLocation,
    [string] [Parameter(Mandatory=$false)] $ResourceGroupName = "001-VM-Virus-Attack-Prevention",
    [string] [Parameter(Mandatory=$false)] $Location = "eastus",
    [switch] $UploadArtifacts,
    [string] $TemplateFile = $ArtifactStagingDirectory + '\azuredeploy.json',
    [string] $TemplateParametersFile = $ArtifactStagingDirectory + '.\azuredeploy.parameters.json'
)

$storageContainerName = "artifacts"

$artifactStagingDirectories = @(
    "$PSScriptRoot\scripts"
    "$PSScriptRoot\nested"
)

$deploymentHash = (Get-StringHash ((Get-AzureRmContext).Subscription.Id)).substring(0, 10)
$storageAccountName = 'azsecstage' + $deploymentHash

New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -Force

Write-Verbose "Check if artifacts storage account exists."
$storageAccount = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName})

# Create the storage account if it doesn't already exist
if ($storageAccount -eq $null) {
    Write-Verbose "Artifacts storage account does not exists."
    Write-Verbose "Provisioning artifacts storage account."
    $storageAccount = New-AzureRmStorageAccount -StorageAccountName $storageAccountName -Type 'Standard_LRS' `
        -ResourceGroupName $ResourceGroupName -Location $Location
    Write-Verbose "Artifacts storage account provisioned."
    Write-Verbose "Creating storage container to upload a blobs."
    New-AzureStorageContainer -Name $storageContainerName -Context $storageAccount.Context -ErrorAction SilentlyContinue *>&1
}
else {
    New-AzureStorageContainer -Name $storageContainerName -Context $storageAccount.Context -ErrorAction SilentlyContinue *>&1
}

if($UploadArtifacts){
    # Copy files from the local storage staging location to the storage account container
    foreach ($artifactStagingDirectory in $artifactStagingDirectories) {
        $ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}
        foreach ($SourcePath in $ArtifactFilePaths) {
            Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring((Split-Path($ArtifactStagingDirectory)).length + 1) `
                -Container $storageContainerName -Context $storageAccount.Context -Force
        }
    }
}

$commonTemplateParameters = New-Object -TypeName Hashtable # Will be used to pass common parameters to the template.
$artifactsLocation = '_artifactsLocation'
$artifactsLocationSasToken = '_artifactsLocationSasToken'

$commonTemplateParameters[$artifactsLocation] = $storageAccount.Context.BlobEndPoint + $storageContainerName
$commonTemplateParameters[$artifactsLocationSasToken] = New-AzureStorageContainerSASToken -Container $storageContainerName -Context $storageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4)

