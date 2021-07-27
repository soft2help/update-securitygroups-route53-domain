# Install AWS PowerShell tools 
# https://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up.html
# Install-Module $module -Scope CurrentUser 
# Scope required if installing without administrative rights
# 


$conf = Get-Content '.env' | ConvertFrom-StringData

# AWS Information, you should create a aws IAM USER with json policies asociated to allow change security group rules and route53 registers
$AccessID=$conf.AWS_ACCESS_KEY_ID
$SecureID=$conf.AWS_SECRET_ACCESS_KEY

$TTL=$conf.TTL
$Domains=$conf.DOMAINS
$SecurityGroups=$conf.SECURITY_GROUPS
$Description=$conf.DESCRIPTION
$Type="A"

Import-Module AWSPowerShell

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
cd $dir

$fileToCheck = "$dir\lastIp.txt"
$lastIp="0.0.0.0"

if (Test-Path $fileToCheck -PathType leaf)
{
    $lastIp = Get-Content $fileToCheck -Raw 
	echo "Last Ip registry ${lastIp}"
	$lastIp = $lastIp.Trim()
}


# Determine public IP address
$IP=(Invoke-WebRequest -uri "http://ifconfig.me/ip").Content
echo "Actual IP ${IP}"

If ($IP -eq $lastIp) # Check to see if the IP value of the record is correct or needs to be updated
{
	echo "The IP not change, i will exit ${lastIp} "	
	Exit
}




$domains= $Domains -split ','

# refresh domain@zoneId in DNS Route53
for ( $index = 0; $index -lt $domains.count; $index++)
{
	$domainZone=$domains[$index] -split '@'
	$domain=$domainZone[0]
	$zoneId=$domainZone[1]

	
    echo "Checking ${dominio} ..."
	
	# Get the current IP address value of the record
	$RecordData=(Test-R53DNSAnswer -AccessKey $AccessID -SecretKey $SecureID -HostedZoneId $zoneId -RecordName $domain -RecordType $type).RecordData
	
	# Set parameters to delete the existng record
    $Delete = New-Object Amazon.Route53.Model.Change
    $Delete.Action = "DELETE"
    $Delete.ResourceRecordSet = New-Object Amazon.Route53.Model.ResourceRecordSet
    $Delete.ResourceRecordSet.Name = $domain
    $Delete.ResourceRecordSet.Type = $Type
    $Delete.ResourceRecordSet.TTL = $TTL
    $Delete.ResourceRecordSet.ResourceRecords.Add(@{Value=$RecordData})

    # Set parameters to create a new record with the correct IP address
    $Create = New-Object Amazon.Route53.Model.Change
    $Create.Action = "CREATE"
    $Create.ResourceRecordSet = New-Object Amazon.Route53.Model.ResourceRecordSet
    $Create.ResourceRecordSet.Name = $domain
    $Create.ResourceRecordSet.Type = $Type
    $Create.ResourceRecordSet.TTL = $TTL
    $Create.ResourceRecordSet.ResourceRecords.Add(@{Value=$IP})

    # Execute the deletion and creation of the record
	echo "Refreshing DNS..."
    Edit-R53ResourceRecordSet -AccessKey $AccessID -SecretKey $SecureID -HostedZoneId $zoneId -ChangeBatch_Change $Delete,$Create
		
}
  


$range=$IP+"/32"

# refreshing security groups 
echo "------------------------------------"
echo "Security Groups"
 
$securityGroupsNames= $SecurityGroups -split ','
for ( $i = 0; $i -lt $securityGroupsNames.Length; $i++)
{
	$securitygroupRegion=$securityGroupsNames[$i] -split '@'
	$securityGroup=$securitygroupRegion[0]
	$region=$securitygroupRegion[1]

	$IpRange = New-Object -TypeName Amazon.EC2.Model.IpRange
	$IpRange.Description = $Description	
	$IpRange.CidrIp = $range

	$ip1 = New-Object Amazon.EC2.Model.IpPermission
	$ip1.IpProtocol = "tcp"
	$ip1.FromPort = 0
	$ip1.ToPort = 65535
	$ip1.Ipv4Ranges = $IpRange
	
	
	
	echo ""
	echo "Checking ${securityGroup} ..."
	
	if (Test-Path $fileToCheck -PathType leaf) {
		echo "Delete rule of the last Ip"
		$lastRange=$lastIp+"/32"
		
		$revoke=@{ IpProtocol="tcp"; FromPort="0"; ToPort="65535"; IpRanges=$lastRange }
		
		Revoke-EC2SecurityGroupIngress -AccessKey $AccessID -SecretKey $SecureID -Force -GroupName $securityGroup -Region $region -IpPermission $revoke 
	}
	
	
	
	echo "Allow access from my actual IP"
	
	
	Grant-EC2SecurityGroupIngress -AccessKey $AccessID -SecretKey $SecureID -Force -GroupName $securityGroup -Region $region -IpPermission $ip1
	
	
	sleep 2
}

echo "SAVING ACTUAL IP"
$IP| Out-File -FilePath $fileToCheck