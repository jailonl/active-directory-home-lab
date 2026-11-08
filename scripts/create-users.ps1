# Builds the OU structure for jlab.local and creates users from users.csv.
# Run on DC01 as a Domain Admin: .\create-users.ps1 -CsvPath C:\Lab\users.csv

param(
    [string]$CsvPath = "C:\Lab\users.csv",
    [string]$DefaultPassword = "Welcome2Lab!"
)

Import-Module ActiveDirectory

$domainDN = (Get-ADDomain).DistinguishedName
$rootOU   = "OU=JLab,$domainDN"

# Top-level OU plus Users, Computers, Groups underneath
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$rootOU'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name "JLab" -Path $domainDN
}
foreach ($ou in "Users", "Computers", "Groups") {
    $dn = "OU=$ou,$rootOU"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $ou -Path $rootOU
    }
}

$users = Import-Csv $CsvPath
$securePw = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force
$upnSuffix = (Get-ADDomain).DNSRoot

foreach ($u in $users) {
    $dept   = $u.Department
    $deptOU = "OU=$dept,OU=Users,$rootOU"
    $group  = "GRP-$dept"

    # One OU and one security group per department
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$deptOU'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $dept -Path "OU=Users,$rootOU"
    }
    if (-not (Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $group -GroupScope Global -GroupCategory Security -Path "OU=Groups,$rootOU"
    }

    # Username format: first initial + last name, e.g. mreed
    $sam = ($u.FirstName.Substring(0,1) + $u.LastName).ToLower()

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Host "Skipping $sam (already exists)"
        continue
    }

    New-ADUser -Name "$($u.FirstName) $($u.LastName)" `
        -GivenName $u.FirstName -Surname $u.LastName `
        -SamAccountName $sam -UserPrincipalName "$sam@$upnSuffix" `
        -Department $dept -Title $u.Title `
        -Path $deptOU -AccountPassword $securePw `
        -ChangePasswordAtLogon $true -Enabled $true

    Add-ADGroupMember -Identity $group -Members $sam
    Write-Host "Created $sam in $dept"
}
