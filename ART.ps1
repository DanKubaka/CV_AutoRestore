#Requires -Version 6.0
$VerbosePreference="Continue"
Set-Location 'C:\Users\kubaka\OneDrive - Danone\_Repositories\AutoRestoreTest'

function CV-Login {
    param($Cred,$CSName)

    $Api = 'https://' + $CSName + '/webconsole/api'
    
    $Hdrs = @{}
    $Hdrs.Add("Host",$CSName)
    $Hdrs.Add("Accept","application/json")
    $Hdrs.Add("Content-type","application/json")

    $Body = @{
        domain     = "NEAD"
        username   = $Cred.UserName
        password   = [convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Cred.GetNetworkCredential().password))
        commserver = $CSName + '*' + $CSName
    }
    $Body = (ConvertTo-Json $Body)
    $Uri = $Api + '/login'

    $timeTaken = Measure-Command -Expression {
        $Result = Invoke-RestMethod -SkipCertificateCheck -SslProtocol Tls12 -Headers $Hdrs -Uri $Uri -Method Post -Body $Body
    }
    $milliseconds = $timeTaken.TotalMilliseconds
    $milliseconds = [Math]::Round($milliseconds, 1)

    Write-Verbose ("Logged in, it took " + $milliseconds + "ms")
    return $Result.token
}

function CV-SubclientProperties {
    param (
        $Token,
        $CSName,
        $SubclientID
    )
    $Hdrs = @{}
    $Hdrs.Add("Host",$CSName)
    $Hdrs.Add("Accept","application/xml")
    $Hdrs.Add("Authtoken",$Token)
    $Hdrs.Add("limit",0)

    $Api = 'https://' + $CSName + '/webconsole/api'
    $Uri = $Api + '/Subclient/' + $SubclientID

    $timeTaken = Measure-Command -Expression {
        $subclientProps = Invoke-RestMethod -SkipCertificateCheck -SslProtocol Tls12 -Headers $Hdrs -Uri $Uri -Method Get
    }
    $milliseconds = $timeTaken.TotalMilliseconds
    $milliseconds = [Math]::Round($milliseconds, 1)

    Write-Verbose ("Subclient properties received, it took " + $milliseconds + "ms")

    return $subclientProps
}

function CV-StoragePolicyDetails {
    param (
        $Token,
        $CSName,
        $StoragePolicyID
    )
    $Hdrs = @{}
    $Hdrs.Add("Host",$CSName)
    $Hdrs.Add("Accept","application/json")
    $Hdrs.Add("Content-type","application/json")
    $Hdrs.Add("Authtoken",$Token)
    $Hdrs.Add("limit",0)
    $Api = 'https://' + $CSName + '/webconsole/api'
    $Uri = $Api + '/V2/StoragePolicy/' + $StoragePolicyID + "?propertyLevel=10"

    $timeTaken = Measure-Command -Expression {
        $storagePolicyDetails = Invoke-RestMethod -SkipCertificateCheck -SslProtocol Tls12 -Headers $Hdrs -Uri $Uri -Method Get
    }
    $milliseconds = $timeTaken.TotalMilliseconds
    $milliseconds = [Math]::Round($milliseconds, 1)

    Write-Verbose ("Storage Policy details received, it took " + $milliseconds + "ms")

    return $storagePolicyDetails
}

function CV-ListSubclients {
    param (
        $Token,
        $CSName,
        $VSA
    )
    $Hdrs = @{}
    $Hdrs.Add("Host",$CSName)
    $Hdrs.Add("Accept","application/json")
    $Hdrs.Add("Content-type","application/json")
    $Hdrs.Add("Authtoken",$Token)
    $Hdrs.Add("limit",0)

    $Api = 'https://' + $CSName + '/webconsole/api'
    $Uri = $Api + '/Subclient?clientName=' + $VSA

    $timeTaken = Measure-Command -Expression {
        $clientbrowse = Invoke-RestMethod -SkipCertificateCheck -SslProtocol Tls12 -Headers $Hdrs -Uri $Uri -Method Get
    }
    $milliseconds = $timeTaken.TotalMilliseconds
    $milliseconds = [Math]::Round($milliseconds, 1)

    Write-Verbose ("Subclients listed, it took " + $milliseconds + "ms")

    $subctable = New-Object System.Collections.ArrayList
    foreach ($subc in $clientbrowse.subClientProperties){

        $storagePolicy = CV-SubclientProperties -Token $Token -CSName $CSName -SubclientID $subc.subClientEntity.SubclientID

        if ($storagePolicy.App_GetSubClientPropertiesResponse.subClientProperties.commonProperties.storageDevice.dataBackupStoragePolicy.storagePolicyId){
            $storagePolicyDetails = CV-StoragePolicyDetails -Token $Token -CSName $CSName -StoragePolicyID $storagePolicy.App_GetSubClientPropertiesResponse.subClientProperties.commonProperties.storageDevice.dataBackupStoragePolicy.storagePolicyId
            $storagePolicy.App_GetSubClientPropertiesResponse.subClientProperties.commonProperties.storageDevice.dataBackupStoragePolicy | Add-Member -NotePropertyName copies -NotePropertyValue $storagePolicyDetails.policies.copies
        }        
        $subc.subClientEntity | Add-Member -NotePropertyName dataBackupStoragePolicy -NotePropertyValue $storagePolicy.App_GetSubClientPropertiesResponse.subClientProperties.commonProperties.storageDevice.dataBackupStoragePolicy
        $subctable.Add($subc.subClientEntity) | Out-Null
    }
    
    return $subctable
}

function CV-BrowseSubclient {
    param (
        $subclient,
        $VSA,
        $Token,
        $CSName
    )
    $Hdrs = @{}
    $Hdrs.Add("Host",$CSName)
    $Hdrs.Add("Accept","application/xml")
    $Hdrs.Add("Content-type","application/xml")
    $Hdrs.Add("Authtoken",$Token)
    $Hdrs.Add("limit",0)

    $Api = 'https://' + $CSName + '/webconsole/api'
    $Uri = $Api + '/DoBrowse'
    
    [xml]$xmldoc = Get-Content ".\Browse.xml"

    $xmldoc.databrowse_BrowseRequest.entity.subclientName = $subclient
    $xmldoc.databrowse_BrowseRequest.entity.clientName = $VSA

    $timeTaken = Measure-Command -Expression {
        $data = Invoke-RestMethod -SkipCertificateCheck -SslProtocol Tls12 -Headers $Hdrs -Uri $Uri -Method Post -Body $xmldoc
    }
    $milliseconds = $timeTaken.TotalMilliseconds
    $milliseconds = [Math]::Round($milliseconds, 1)

    Write-Verbose ("Subclient browsed, it took " + $milliseconds + "ms")

    return $data.databrowse_BrowseResponseList.browseResponses[0].browseResult.dataResultSet
}

function CV-ListVMs {
    param (
        $Token,
        $CSName,
        $subclients,
        $VSA
    )
    
    $vmtable= New-Object System.Collections.ArrayList
    foreach ($subc in $subclients){
        $vmlist = CV-BrowseSubclient -VSA $VSA -subclient $subc.subclientName -Token $Token -CSName $CSName
        foreach ($vm in $vmlist){
                $vm | Add-Member -NotePropertyName subClient -NotePropertyValue $subc
                $vmtable.add($vm) | Out-Null
            }
    }
    return $vmtable
}

function CV-BrowseVM {
    param (
        $VM,
        $Token,
        $CSName,
        $CopyPrecedence
    )

    $Hdrs = @{}
    $Hdrs.Add("Host",$CSName)
    $Hdrs.Add("Accept","application/xml")
    $Hdrs.Add("Content-type","application/xml")
    $Hdrs.Add("Authtoken",$Token)
    $Hdrs.Add("limit",0)

    $Api = 'https://' + $CSName + '/webconsole/api'
    $Uri = $Api + '/DoBrowse'
    
    [xml]$xmldoc = Get-Content ".\Browse.xml"

    $xmldoc.databrowse_BrowseRequest.entity.subclientName = $VM.subClient.subclientName
    $xmldoc.databrowse_BrowseRequest.entity.backupsetName = $VM.subClient.backupsetName
    $xmldoc.databrowse_BrowseRequest.entity.instanceName = $VM.subClient.instanceName
    $xmldoc.databrowse_BrowseRequest.entity.appName = $VM.subClient.appName
    $xmldoc.databrowse_BrowseRequest.entity.clientName = $VM.subClient.clientName

    $xmldoc.databrowse_BrowseRequest.paths.path = $VM.path

    $xmldoc.databrowse_BrowseRequest.advOptions.copyPrecedence = $CopyPrecedence

    $timeTaken = Measure-Command -Expression {
        $data = Invoke-RestMethod -SkipCertificateCheck -SslProtocol Tls12 -Headers $Hdrs -Uri $Uri -Method Post -Body $xmldoc
    }
    $milliseconds = $timeTaken.TotalMilliseconds
    $milliseconds = [Math]::Round($milliseconds, 1)

    Write-Verbose ("VM browsed, it took " + $milliseconds + "ms")

    return $data.databrowse_BrowseResponseList.browseResponses[0].browseResult.dataResultSet
}

function PrepareRestoreXML {
    param (
        $inputParam,
        $browseData,
        $restoreParam
    )
    
    [xml]$restorexml = Get-Content .\VMRestoreTemplate.xml


    ##
    #New (restore) parameters
    
    $restorexml.TMMsg_CreateTaskReq.taskInfo.associations.subclientName = $browseData.subclientName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.associations.backupsetName = $browseData.backupsetName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.associations.instanceName = $browseData.instanceName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.associations.appName = $browseData.appName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.associations.clientName = $browseData.vsa
    
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.browseOption.backupset.backupsetName = $browseData.backupsetName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.browseOption.backupset.instanceName = $browseData.instanceName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.browseOption.backupset.appName = $browseData.appName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.browseOption.backupset.clientName = $browseData.vmName
    
    #$restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.browseOption.timeZone = ??
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.destination.destClient.clientName = $restoreParam.proxyName
    
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.esxServerName = $restoreParam.subscription.$($inputParam.region)
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.guid = $browseData.vmGuid
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.name = $browseData.vmName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.newName = $restoreParam.vmNewName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.esxHost = $restoreParam.resourceGroup
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.Datastore = $restoreParam.datastore
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.vmSize = $browseData.vmSize
    
    #for each disk browsed:
    <#
    $diskCount = 0;
    foreach ($file in $thisvmbrowse){
        if ($file.name -notlike '*.json') { 
            $diskCount++;
        }
    }
    
    
    for ($i=1;$i -lt $diskCount;$i++){
        $diskNode = $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.disks.Clone()
        $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.AppendChild($diskNode)
    }
    #>
    
    $diskNode = $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.disks.Clone()
    foreach ($file in $browseData.disks){
        if ($file.name -notlike '*.json'){
            $diskNode.name = $file.name
            $diskNode.datastore = $restoreParam.datastore
            $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.AppendChild($diskNode) | Out-Null
            $diskNode = $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.disks[0].Clone()
        }
    }
    $diskNodeZero = $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.disks[0]
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.RemoveChild($diskNodeZero) | Out-Null
    
    #nics // Static
    
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.nics.name = $restoreParam.nic.Name
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.nics.networkName = $restoreParam.nic.networkName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.nics.subnetId = $restoreParam.nic.subnetID
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.nics.networkDisplayName = $restoreParam.nic.networkDisplayName
    
    <#NSG // Static
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.securityGroups.groupId = NSG_ID
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.securityGroups.groupName = NSG NAME
    #>
    
    #Managed VM ??
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.diskLevelVMRestoreOption.advancedRestoreOptions.restoreAsManagedVM = $browseData.vmManaged
    
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.vCenterInstance.instanceName = $browseData.instanceName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.vCenterInstance.appName = $browseData.appName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.virtualServerRstOption.vCenterInstance.clientName = $browseData.vsa
    
    #fileoptions:
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.fileOption.sourceItem = $browseData.path
    #$restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.restoreOptions.fileOption.browseFilters = ?? Probably dont use
    
    #VM node:
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].browsePath = $browseData.vmName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].vmGUID = $browseData.vmGuid
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].esxHost = $restoreParam.resourceGroup
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].datastore = $restoreParam.datastore
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].nics.name = $restoreParam.nic.Name
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].nics.networkName = $restoreParam.nic.networkName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].nics.subnetID = $restoreParam.nic.subnetID
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].nics.networkDisplayName = $restoreParam.nic.networkDisplayName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].vmDataStore = $restoreParam.datastore
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].vmEsxHost = $restoreParam.resourceGroup
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].DisplayName = $browseData.vmName
    $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[0].diskType = 0
    
    $diskBrowseNode = $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[1]
    
    #file Nodes
    foreach ($file in $browseData.disks){
            $diskBrowseNode.browsePath = $file.displayPath.Substring(1)
            $diskBrowseNode.vmGUID = $browseData.vmGuid
    
            if ($file.name -like '*json'){
                $diskBrowseNode.vmDataStore = $browseData.vmDataStore
                $diskBrowseNode.esxHost = ""
                $diskBrowseNode.datastore = ""
            }
            else {
                $diskBrowseNode.vmDataStore = $restoreParam.datastore
                $diskBrowseNode.esxHost = $browseData.vmResourceGroup
                $diskBrowseNode.datastore =  $restoreParam.datastore
            }
            $diskBrowseNode.vmEsxHost = $browseData.vmResourceGroup
            $diskBrowseNode.isDriveNode = 'false'
            $diskBrowseNode.isMetadataAvaiable = 'true'
            $diskBrowseNode.DisplayName = $file.displayName
            $diskBrowseNode.diskType = $file.advancedData.browseMetaData.virtualServerMetaData.diskType
            $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.AppendChild($diskBrowseNode) | Out-Null
            $diskBrowseNode = $restorexml.TMMsg_CreateTaskReq.taskInfo.subTasks.options.vmBrowsePathNodes[1].Clone()
    }
    
    $restorexml.Save(".\RecreatedXML_BENL.xml")
    return $restorexml
}

function CV-RestoreVM {
    param (
        $Token,
        $restorexml,
        $CSName
    )

    $Hdrs = @{}
    $Hdrs.Add("Host",$CSName)
    $Hdrs.Add("Accept","application/xml")
    $Hdrs.Add("Content-type","application/xml")
    $Hdrs.Add("Authtoken",$Token)
    $Hdrs.Add("limit",0)

    $Api = 'https://' + $CSName + '/webconsole/api'
    $Uri = $Api + '/QCommand/qoperation execute'

    $timeTaken = Measure-Command -Expression {
        $resp = Invoke-RestMethod -SkipCertificateCheck -SslProtocol Tls12 -Headers $Hdrs -Uri $Uri -Method Post -Body $restorexml
    }
    $milliseconds = $timeTaken.TotalMilliseconds
    $milliseconds = [Math]::Round($milliseconds, 1)

    Write-Verbose ("Restore task created, it took " + $milliseconds + "ms")

    return $resp
}

$inputParam = @{
    cred = Import-Clixml -Path $HOME\adm.cred
    csName = 'Dancommserve'
    vmName = "wfrparnlb030"
    region = "BENL"
    vsa = @{
        NCE = "VSA_EU_NCE"
        EE = "VSA_EU_EE"
        MEESA = "VSA_EU_MEESA"
        UKI = "VSA_EU_UKI"
        DACH = "VSA_EU_DACH"
        BENL = "VSA_EU_BENL"
    }
    restore = @{
        proxyName = @{
            NCE = "wfrparpli015"
            EE = "wfrparczi001"
            MEESA = "wfrparegi001"
            UKI = "wfrparuki001"
            DACH = "wfrpardei001"
            BENL = "wfrparnli001"
        } #DR bedzie nowy, RT: osobno kazdy
        #resourceGroup = "...RestoreTests"
        datastore = "danplpsta998lrs" #DR: nowy pojedynczy, RT: konkretny z regionu pod RT # jesli filer -> ten sam datastore co poprzednio
    }
}

$StartMs = Get-Date

$token = CV-Login -Cred $inputParam.Cred -CSName $inputParam.CSName

$subclients = CV-ListSubclients -Token $token -CSName $inputParam.CSName -VSA $inputParam.vsa.$($inputParam.region) | Where-Object {$_.backupsetName -eq "defaultBackupSet"}
$vmtable = CV-ListVMs -Token $token -CSName $inputParam.CSName -subclients $subclients -VSA $inputParam.vsa.$($inputParam.region)
$EndMs = Get-Date

Write-Verbose ("Data collection took: " + $($EndMs - $StartMs).TotalSeconds  + " seconds")


$StartMs = Get-Date
$thisvm = $vmtable | Where-Object {$_.displayName -eq $inputParam.vmName}

if ($thisvm){
    Write-Verbose "VM found"
}
else{
    Write-Verbose "VM not found"
    Write-Error "VM not found"
    exit
}

#Add copy precendence choosing
<#
Weak Filer check 

if($inputParam.vmName.Substring($inputParam.vmName.Length-4,1) -eq "f"{
    $filer = 1
}

#>
$copyPrecedence = "0"
if (0<#DRP#>){
    $copyPrecedence = $($thisvm.subClient.dataBackupStoragePolicy.copies | Where-Object {$_.storagePolicyCopy.copyName -match 'DRP'}).copyPrecedence
}
else{
    if (0<#filer#>){
        $copyPrecedence = $($thisvm.subClient.dataBackupStoragePolicy.copies | Where-Object {$_.storagePolicyCopy.copyName -match 'snap'}).copyPrecedence
        #same datastore
    }
    else {
        $copyPrecedence = $($thisvm.subClient.dataBackupStoragePolicy.copies | Where-Object {$_.storagePolicyCopy.copyName -like 'Primary'}).copyPrecedence
    }
}

## BROWSING VM
$thisvmbrowse = CV-BrowseVM -VM $thisvm -Token $token -CSName $inputParam.CSName -CopyPrecedence $copyPrecedence
######


#Prepare parameters
[String]$managed = [boolean]$thisvm.advancedData.browseMetaData.virtualServerMetaData.managedVM.ToString()
$nics = $([xml]$thisvm.advancedData.browseMetaData.virtualServerMetaData.nics).IdxMetadata_VMNetworks.nic

$browseData =@{
    subclientName = $thisvm.subClient.subclientName
    backupsetName = $thisvm.subClient.backupsetName
    instanceName = $thisvm.subClient.instanceName
    appName = $thisvm.subClient.appName
    vmName = $inputParam.vmName
    vmGuid = $thisvm.name
    vmSize = $thisvm.advancedData.browseMetaData.virtualServerMetaData.instanceSize
    vmResourceGroup = $thisvm.advancedData.browseMetaData.virtualServerMetaData.esxHost
    vmDataStore = $thisvm.advancedData.browseMetaData.virtualServerMetaData.datastore
    path = $thisvm.path
    vmManaged = $managed
    vsa = $inputParam.vsa.$($inputParam.region)
    disks = $thisvmbrowse
    nics = $nics    
}

$resourceGroup = $thisvm.advancedData.browseMetaData.virtualServerMetaData.esxHost -replace "-P-", "-R-"

$restorenic = $nics
$restorenic.subnet = $restorenic.subnet -replace "-P-", "-R-"
$tempA = $restorenic.subnet.Split("/virtualNetworks/")
$tempB = $tempA[1].Split("/subnets/")
$tempC = $restorenic.subnet.Split("/subnets")

$nicName = $tempC[0]
$networkName = $tempB[0]
$subnetName = $tempB[1]
$subnetId = $restorenic.subnet


$restoreParam = @{
    subscription = @{
        NCE = "7cbc458e-c416-4ce8-bece-d8e3e403b5a0"
        EE = "ccbcdedf-1910-43ba-a3ad-467ee1157c76"
        MEESA = "dcd04b65-2843-4939-9b25-f9fca97e80da"
        UKI = "65a414a4-300b-468d-85e1-6c338e1acd7b"
        DACH = "122aa6f7-3063-408a-875f-77dfb5af533f"
        BENL = "6de6133f-ee8f-48ac-abfe-06b9b0f9e138"
        }
    resourceGroup = $resourceGroup
    #resourceGroup = $inputParam.restore.resourceGroup
    vmNewName = "RT" + $inputParam.vmName #the same if DR
    datastore = $inputParam.restore.datastore
    proxyName = $inputParam.restore.proxyName.$($inputParam.region)
    nic = @{
        Name = $nicName
        networkName = $networkName
        subnetID = $subnetId
        networkDisplayName = $networkName + "\" + $subnetName 
    }
}

$restorexml = PrepareRestoreXML -inputParam $inputParam -browseData $browseData -restoreParam $restoreParam

$EndMs = Get-Date

Write-Verbose ("Restore job creation took: " + $($EndMs - $StartMs).TotalSeconds + " seconds")

$VerbosePreference="SilentlyContinue"