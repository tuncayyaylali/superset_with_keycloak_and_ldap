# ==============================================================================
# Script: Create Sample LDAP User and Assign Group Membership
# User: david.finance | Group: bi-finance-viewers
# ==============================================================================

$Namespace = "superset-bi"
$ErrorActionPreference = "Continue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " [LDAP Provisioning] Creating New Sample User: david.finance     " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

$LdapPod = (kubectl get pods -n $Namespace -l app=openldap -o jsonpath="{.items[0].metadata.name}")

# 1. Create User Entry in ou=users,dc=example,dc=org
$UserLdif = @"
dn: uid=david.finance,ou=users,dc=example,dc=org
changetype: add
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: david.finance
cn: David Finance
givenName: David
sn: Finance
mail: david.finance@example.org
userPassword: Password123!
"@

Write-Host "Adding user 'david.finance' to LDAP..." -ForegroundColor Yellow
$UserLdif | kubectl exec -i -n $Namespace $LdapPod -- ldapmodify -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w adminpassword

# 2. Add User to Group: cn=bi-finance-viewers,ou=groups,dc=example,dc=org
$GroupLdif = @"
dn: cn=bi-finance-viewers,ou=groups,dc=example,dc=org
changetype: modify
add: member
member: uid=david.finance,ou=users,dc=example,dc=org
"@

Write-Host "`nAdding 'david.finance' to group 'bi-finance-viewers'..." -ForegroundColor Yellow
$GroupLdif | kubectl exec -i -n $Namespace $LdapPod -- ldapmodify -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w adminpassword

# 3. Verify User and Group in LDAP
Write-Host "`nVerifying 'david.finance' in OpenLDAP..." -ForegroundColor Yellow
$VerifyUser = kubectl exec -n $Namespace $LdapPod -- ldapsearch -x -H ldap://localhost:389 -b "ou=users,dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -w adminpassword "(uid=david.finance)" uid mail
Write-Host $VerifyUser -ForegroundColor Gray

$VerifyGroup = kubectl exec -n $Namespace $LdapPod -- ldapsearch -x -H ldap://localhost:389 -b "ou=groups,dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -w adminpassword "(cn=bi-finance-viewers)" member
Write-Host $VerifyGroup -ForegroundColor Gray

if ($VerifyUser -match "david.finance" -and $VerifyGroup -match "david.finance") {
    Write-Host "`n[SUCCESS] User 'david.finance' successfully created and added to 'bi-finance-viewers'!" -ForegroundColor Green
} else {
    Write-Warning "User or group membership verification failed."
}

