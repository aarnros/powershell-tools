
Add-Type -AssemblyName System.Windows.Forms
$Form1 = New-Object -TypeName System.Windows.Forms.Form
$ADList = @("example1.dom", "example2.dom")
$global:userData = @{}

#region Declaration
[System.Windows.Forms.RadioButton]$CmpBtn = $null
[System.Windows.Forms.RadioButton]$UserBtn = $null

[System.Windows.Forms.TextBox]$SearchBox = $null # Renamed from $PCNameInput
[System.Windows.Forms.Button]$SearchButton = $null
[System.Windows.Forms.CheckBox]$EnforceNameLen = $null
[System.Windows.Forms.ComboBox]$UserDropdown = $null
[System.Windows.Forms.LinkLabel]$CmpNumberLabel = $null
[System.Windows.Forms.Button]$OpenDriveButton = $null   
[System.Windows.Forms.LinkLabel]$FQDNLabel = $null
[System.Windows.Forms.LinkLabel]$IPLabel = $null
[System.Windows.Forms.CheckBox]$AutoCopyIP = $null
[System.Windows.Forms.Label]$CmpOULabel = $null
[System.Windows.Forms.Label]$NameLabel = $null
[System.Windows.Forms.LinkLabel]$UsernameLabel = $null
[System.Windows.Forms.Button]$ADButton = $null
[System.Windows.Forms.Label]$UptimeLabel = $null
[System.Windows.Forms.Label]$LockedLabel = $null
[System.Windows.Forms.Button]$UnlockButton = $null
[System.Windows.Forms.LinkLabel]$OpenLockoutStatus = $null
[System.Windows.Forms.Label]$UserOULabel = $null
[System.Windows.Forms.Button]$SoftwareButton = $null


#endregion Declartion


#region Listeners
$UserBtn_CheckedChanged = {
    $EnforceNameLen.Visible = $false
}
$CmpBtn_CheckedChanged = {
    $EnforceNameLen.Visible = $true
}
$SearchButton_Click = {
    # $Global:verifCmpNum = $null
    $searchTerm = $SearchBox.Text.Trim()
    $nameLen = $searchTerm.length
    if ($nameLen -eq 0) {
        PopupMsg "Cannot Search with an Empty String" -msgTitle "Empty Search" -iconType 16
        return
    }
    #region Computer Search
    if ($CmpBtn.Checked -eq $true) {
        $pcName = $searchTerm.ToUpper()
        if ($EnforceNameLen.Checked -eq $true) {
            if ($nameLen -ne 10) {
                PopupMsg "Entered PC name is $nameLen not 10 characters long"
                return
            }
        }
        $results = QueryADCmp $pcName
        If ($null -eq $results) {
            PopupMsg "PC not found in AD" -msgTitle "PC not found" -iconType 16
        }
        else {
            $timeUp = "N/A"
        $timeUp = GetRemoteUptime $pcName
        $global:userData['pcNum'] = $pcName 
        $global:userData['FQDN']=$results[0].DNSHostName 
        $global:userData['ip']=$results[0].IPV4Address
        if ($AutoCopyIP.Checked -eq $true) {
            Set-Clipboard -Value $global:userData['ip']
        }
        $global:userData['uptime']=$timeUp
        $global:userData['cmpOU']=$results[0].CanonicalName
        $global:userData['server']=$results[1]
        GetUsers
        UpdateWindow -user $true -cmp $true
        # PopupMsg "PC found in AD" -msgTitle "PC found" -iconType 64
    }
    }else{
        UpdateWindow -reset $true -cmp $true 
        QueryADUser $searchTerm
        UpdateWindow -user $true
    }

}
    #endregion Computer Search
$OpenDriveButton_Click = {
    Invoke-Item -Path ("\\" + $global:userData['pcNum'] + "\c$") #change to $pcName when implemented
}
$UserDropdown_SelectedIndexChanged = {
    QueryADUser $UserDropdown.SelectedItem
    UpdateWindow -user $true
}
#endregion Listeners
$CmpNumberLabel_Click = { Set-Clipboard -Value $global:userData['pcNum']}
$FQDNLabel_Click = {Set-Clipboard -Value $global:userData['FQDN']}
$IPLabel_Click = {Set-Clipboard -Value $global:userData['ip']}
$UsernameLabel_Click = {Set-Clipboard -Value $global:userData['username']}
$ADButton_Click = { PopupMsg "AD not yet implemented" }
$UnlockButton_Click = { UnlockUser $global:userData['username']}
$OpenLockoutStatus_Click = {
    try{
        $fullName = $global:userData['username'] + "@" + $global:userData['server']
        C:\Software\LockoutStatus.exe -u:$fullName
    }catch{PopupMsg "Unable to Open LockoutStatus" -msgTitle "Unable to Open LockoutStatus" -iconType 16}
}
$SoftwareButton_Click = { Invoke-Item -path "\\pwscl01cohcm01.wintrust.wtfc\ServiceDesk"}
#region Functions
function PopupMsg { 
    param (
        [Parameter(Position = 0, mandatory = $true)]$Message,
        [string]$msgTitle = "Warning",
        [int16]$buttonType = 0,
        [int16]$iconType = 48
    )
    [System.Windows.Forms.MessageBox]::Show($Message, $msgTitle, $buttonType, $iconType) 
}
function UnlockUser {
    param (
        $user
    )
    try{
        $passwordServers = Get-ADGroupMember -server $global:userData['server'] "Domain Controllers" | Select-Object Name
        foreach ($server in $passwordServers){
            Unlock-ADAccount $user -server $server
        }
    }catch{
        PopupMsg "Unable To Unlock" -msgTitle "Unlock Unsuccessful"
    }

}
function QueryADCmp {
    param($cmpNum)
    Import-Module ActiveDirectory
    foreach ($domain in $ADList) {
        $queryADPC = Get-ADComputer -Filter "Name -like '$cmpNum'" -Server $domain -Properties CanonicalName, IPV4Address 
        if ($null -ne $queryADPC) {
            return @($queryADPC, $domain)
        }
    }
}

function GetUsers {
    try {
        $queryUsers = (quser /server $global:userData.pcNum) -ireplace '\s{2,}',',' | ConvertFrom-CSV 
        $usernames = $queryUsers.username
        $UserDropdown.Items.Clear()
        if ($usernames.GetType().Name -eq 'String'){
            QueryADUser $usernames
        }else{
                $UserDropdown.Items.AddRange($usernames)
            }
    }catch {
        PopupMsg -Message "Cannot Get Users"
    }
}
Function QueryADUser{
    param($user)
    # if ('server' -notin $global:userData.Keys){
    if($null -eq $global:userData['server']){
        foreach ($domain in $ADList){
            $QueryAD =  Get-ADUser -Filter "SamAccountName -eq '$user'" -server $domain -Properties CanonicalName,PasswordExpired,LockedOut
            if($null -ne $QueryAD){
                $global:userData['username'] = $QueryAD.SamAccountName
                $global:userData['name'] = $QueryAD.Name
                $global:userData['locked'] = $QueryAD.LockedOut
                $global:userData['userOU'] = $QueryAD.CanonicalName
                $global:userData['server'] = $domain
                break
            }
        }
    }else{
    $QueryAD = Get-ADUser -Filter "SamAccountName -eq '$user'" -server $global:userData['server'] -Properties CanonicalName,PasswordExpired,LockedOut
}
if($null -ne $QueryAD){
    $global:userData['username'] = $QueryAD.SamAccountName
    $global:userData['name'] = $QueryAD.Name
    $global:userData['locked'] = $QueryAD.LockedOut
    $global:userData['userOU'] = $QueryAD.CanonicalName
}
}
function GetRemoteUptime {
    param (
        $pcName
    )
    try{
        [string]$BootTimeString = (Get-WmiObject win32_operatingsystem -ComputerName $pcName).lastbootuptime -replace '\..*', ''
        $BootTimeDT = [datetime]::ParseExact($BootTimeString, 'yyyyMMddHHmmss', $null)
        $Diff = (Get-Date) - $BootTimeDT
        return $Diff.ToString("dd' days 'hh' hours 'mm' minutes 'ss' seconds'")
    }catch{
        PopupMsg -Message "Cannot get Uptime"
    }
}

function UpdateWindow {
    param (
        $resultobj,
        $reset = $false,
        $cmp = $false,
        $user = $false
    )
    if ($reset -eq $true) {
        if($cmp -eq $true){
        $CmpNumberLabel.Text = [System.String]"Computer Number: N/A"
        $FQDNLabel.Text = [System.String]"FQDN: N/A"
        $IPLabel.Text = [System.String]"IP: N/A"
        $UptimeLabel.Text = [System.String]"Uptime: N/A"
        $CmpOULabel.Text = [System.String]"Computer OU: N/A"
        }
        if ($user -eq $true){
        $NameLabel.Text = [System.String]"Name: N/A"
        $UsernameLabel.Text = [System.String]"Username: N/A"
        $LockedLabel.Text = [System.String]"Locked: N/A"
        $UserOULabel.Text = [System.String]"User OU: N/A"
        }
        return
    }
    if($cmp -eq $true){
    $CmpNumberLabel.Text = [System.String]"Computer Number: " + $global:userData['pcNum']
    $FQDNLabel.Text = [System.String]"FQDN: " + $global:userData['FQDN']
    $IPLabel.Text = [System.String]"IP: " + $global:userData['ip']
    $UptimeLabel.Text = [System.String]"Uptime: " + $global:userData['uptime']
    $CmpOULabel.Text = [System.String]"Computer OU: " + $global:userData['cmpOU'] 
    }
    if ($user -eq $true){
        $NameLabel.Text = [System.String]"Name: " + $global:userData['name']
        $UsernameLabel.Text = [System.String]"Username: " + $global:userData['username']
        $LockedLabel.Text = [System.String]"Locked: " + $global:userData['locked']
        $UserOULabel.Text = [System.String]"User OU: " + $global:userData['userOU']
    }

}
#endregion Functions
function InitializeComponent {
    #region Resources
    $resources = & { $BinaryFormatter = New-Object -TypeName System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
        @{ 
            '$this.Name'        = 'Form1'
            'UserBtn.Name'      = 'UserBtn'
            'CmpBtn.Name'       = 'CmpBtn'
            'SearchButton.Name' = 'SearchButton'
            'SearchBox.Name'    = 'SearchBox'
            'UnlockButton.Name' = 'UnlockButton'
        }
    }
    #endregion Resources



    #region Instantiate Objects
    $CmpBtn = (New-Object -TypeName System.Windows.Forms.RadioButton)
    $UserBtn = (New-Object -TypeName System.Windows.Forms.RadioButton)
    $SearchBox = (New-Object -TypeName System.Windows.Forms.TextBox)
    $SearchButton = (New-Object -TypeName System.Windows.Forms.Button)
    $EnforceNameLen = (New-Object -TypeName System.Windows.Forms.CheckBox)
    $UserDropdown = (New-Object -TypeName System.Windows.Forms.ComboBox)
    $CmpNumberLabel = (New-Object -TypeName System.Windows.Forms.LinkLabel)
    $OpenDriveButton = (New-Object -TypeName System.Windows.Forms.Button)
    $FQDNLabel = (New-Object -TypeName System.Windows.Forms.LinkLabel)
    $IPLabel = (New-Object -TypeName System.Windows.Forms.LinkLabel)
    $AutoCopyIP = (New-Object -TypeName System.Windows.Forms.CheckBox)
    $CmpOULabel = (New-Object -TypeName System.Windows.Forms.Label)
    $NameLabel = (New-Object -TypeName System.Windows.Forms.Label)
    $UsernameLabel = (New-Object -TypeName System.Windows.Forms.LinkLabel)
    $ADButton = (New-Object -TypeName System.Windows.Forms.Button)
    $UptimeLabel = (New-Object -TypeName System.Windows.Forms.Label)
    $LockedLabel = (New-Object -TypeName System.Windows.Forms.Label)
    $UnlockButton = (New-Object -TypeName System.Windows.Forms.Button)
    $OpenLockoutStatus = (New-Object -TypeName System.Windows.Forms.LinkLabel)
    $UserOULabel = (New-Object -TypeName System.Windows.Forms.Label)
    $SoftwareButton = (New-Object -TypeName System.Windows.Forms.Button)
    

    #endregion Instantiate Objects
    
    #region Form Properties
    #region Radio Buttons 
    #region Properties 
    $btn_spacing = 4
    $CmpBtn_Size = @(80, 24)
    $UserBtn_Size = @(52, 24)
    $btn_Y_Loc = 9
    $init_X_Loc = 3
    $UserBtn_X_Loc = $CmpBtn_Size[0] + $btn_spacing
    $Form_Size = @(454, 486)
    #endregion Properties 
    #region Computer Button 
    $CmpBtn.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]$init_X_Loc, [System.Int32]$btn_Y_Loc))
    $CmpBtn.Name = [System.String]'CmpBtn'
    $CmpBtn.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $CmpBtn_Size)
    $CmpBtn.TabIndex = [System.Int32]0
    $CmpBtn.TabStop = $true
    $CmpBtn.Text = [System.String]'Computer'
    $CmpBtn.UseVisualStyleBackColor = $true
    $CmpBtn.Checked = $true
    $CmpBtn.add_CheckedChanged($CmpBtn_CheckedChanged)
    #endregion Computer Button
    #region User Button
    $UserBtn.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]$UserBtn_X_Loc, [System.Int32]$btn_Y_Loc))
    $UserBtn.Name = [System.String]'UserBtn'
    $UserBtn.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $UserBtn_Size)
    $UserBtn.TabIndex = [System.Int32]1
    $UserBtn.TabStop = $true
    $UserBtn.Text = [System.String]'User'
    $UserBtn.UseVisualStyleBackColor = $true
    $UserBtn.add_CheckedChanged($UserBtn_CheckedChanged)
    #endregion User Button
    #endregion Radio Buttons 
    #region Search
    #region Properties
    #region Size
    $SearchBox_Size = @(170, 20)
    $SearchButton_Size = @(75, 22)
    $EnforceNameLen_Size = @(100, 20)
    $Dropdown_Size = @(170, 20)
    #endregion Size
    #region Location
    $Search_Y_Loc = 9
    $SearchBox_X_Loc = $UserBtn_X_Loc + $UserBtn_Size[0] + $btn_spacing
    $SearchButton_X_Loc = $SearchBox_X_Loc + $SearchBox_Size[0] + $btn_spacing
    $EnforceNameLen_Y_Loc = $btn_Y_Loc + $CmpBtn_Size[1] + $btn_spacing
    $Dropdown_X_Loc = $SearchBox_X_Loc
    #endregion Location
    #endregion Properties
    #region Search Box
    $SearchBox.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]$SearchBox_X_Loc, [System.Int32]$Search_Y_Loc))
    $SearchBox.Name = [System.String]'SearchBox'
    $SearchBox.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $SearchBox_Size)
    $SearchBox.TabIndex = [System.Int32]3
    #endregion Search Box
    #region Search Button
    $SearchButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]$SearchButton_X_Loc, [System.Int32]$Search_Y_Loc))
    $SearchButton.Name = [System.String]'SearchButton'
    $SearchButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $SearchButton_Size)
    $SearchButton.TabIndex = [System.Int32]2
    $SearchButton.Text = [System.String]'Search'
    $SearchButton.UseVisualStyleBackColor = $true
    $SearchButton.add_Click($SearchButton_Click)
    $SearchButton.Anchor = [System.Windows.Forms.AnchorStyles]([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
    #endregion Search Button
    #region Enforce Name Length
    $EnforceNameLen.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]$init_X_Loc, [System.Int32]$EnforceNameLen_Y_Loc))
    $EnforceNameLen.AutoSize = $true
    $EnforceNameLen.Name = [System.String]'EnforceNameLen'
    $EnforceNameLen.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $EnforceNameLen_Size)
    $EnforceNameLen.Text = [System.String]'Enforce Name Length'
    $EnforceNameLen.UseVisualStyleBackColor = $true
    $EnforceNameLen.Checked = $true
    #endregion Enforce Name Length
    #region User Dropdown
    $UserDropdown.FormattingEnabled = $true
    $UserDropdown.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]$Dropdown_X_Loc, [System.Int32]37))
    $UserDropdown.Name = [System.String]'UserDropdown'
    $UserDropdown.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $Dropdown_Size)
    $UserDropdown.add_SelectedIndexChanged($UserDropdown_SelectedIndexChanged)
    #endregion User Dropdown
    #endregion Search
    #region Results
    #region Properties
    $FirstLvl_Font = @([System.String]'Tahoma', [System.Single]12)
    $SecondLvl_Font = @([System.String]'Tahoma', [System.Single]8)

    $AutoCopyIP_Size = @(100, 20)
    $OU_Size = @(250, 40)
    $ADButton_Size = @(100, 20)
    $UnlockButton_Size = @(100, 20)
    $OpenLockoutStatus_Size = @(100, 20)
    $FirstLvl_Size = @(300, 20)
    $SecondLvl_Size = @(250, 20)
    $OpenDriveButton_Size = @(100, 20)
    $SoftwareButton_Size = @(140, 20)
    #region Location
    $Results_Start_Y_Loc = 50 + $EnforceNameLen_Y_Loc + $EnforceNameLen_Size[1]
    $FirstLvl_X_Loc = 10
    $SecondLvl_X_Loc = 2 * $FirstLvl_X_Loc
    $OpenDriveButton_X_Loc = $Form_Size[0] - $OpenDriveButton_Size[0] - $FirstLvl_X_Loc
    $FQDNLabel_Y_Loc = $Results_Start_Y_Loc + $FirstLvl_Size[1] + $btn_spacing
    $IPLabel_Y_Loc = $FQDNLabel_Y_Loc + $SecondLvl_Size[1] + $btn_spacing
    $AutoCopyIP_X_Loc = $Form_Size[0] - $AutoCopyIP_Size[0] - $FirstLvl_X_Loc
    $UptimeLabel_Y_Loc = $IPLabel_Y_Loc + $FirstLvl_Size[1] + $btn_spacing
    $CmpOULabel_Y_Loc = $UptimeLabel_Y_Loc + $FirstLvl_Size[1] + $btn_spacing
    $NameLabel_Y_Loc = $CmpOULabel_Y_Loc + $OU_Size[1] + $btn_spacing
    $UsernameLabel_Y_Loc = $NameLabel_Y_Loc + $FirstLvl_Size[1] + $btn_spacing
    $ADButton_X_Loc = $Form_Size[0] - $ADButton_Size[0] - $FirstLvl_X_Loc
    $LockedLabel_Y_Loc = $UsernameLabel_Y_Loc + $FirstLvl_Size[1] + $btn_spacing
    $UnlockButton_X_Loc = $Form_Size[0] - $UnlockButton_Size[0] - $FirstLvl_X_Loc
    $OpenLockoutStatus_X_Loc = $Form_Size[0] - $OpenLockoutStatus_Size[0] - $FirstLvl_X_Loc 
    $OpenLockoutStatus_Y_Loc = $LockedLabel_Y_Loc + $UnlockButton_Size[1] + $btn_spacing
    $UserOULabel_Y_Loc = $LockedLabel_Y_Loc + $FirstLvl_Size[1] + $btn_spacing
    $SoftwareButton_X_Loc = $Form_Size[0] - $SoftwareButton_Size[0] - $FirstLvl_X_Loc
    $SoftwareButton_Y_Loc = $Form_Size[1] - $SoftwareButton_Size[1] - $btn_spacing
    #endregion Location
    #endregion Properties
    #region Computer Number
    $CmpNumberLabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]$FirstLvl_X_Loc, [System.Int32]$Results_Start_Y_Loc))
    $CmpNumberLabel.Name = [System.String]'CmpNumberLabel'
    $CmpNumberLabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $FirstLvl_Size)
    $CmpNumberLabel.Font = (New-Object -TypeName System.Drawing.Font -ArgumentList $FirstLvl_Font)
    $CmpNumberLabel.add_Click($CmpNumberLabel_Click)
    #endregion Computer Number
    #region Open Drive Button
    $OpenDriveButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]$OpenDriveButton_X_Loc, [System.Int32]$Results_Start_Y_Loc))
    $OpenDriveButton.Name = [System.String]'OpenDriveButton'
    $OpenDriveButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $OpenDriveButton_Size)
    $OpenDriveButton.Text = [System.String]'Open Drive'
    $OpenDriveButton.add_Click($OpenDriveButton_Click)
    #endregion Open Drive Button
    #region FQDN
    $FQDNLabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $SecondLvl_X_Loc, $FQDNLabel_Y_Loc)
    $FQDNLabel.Name = [System.String]'FQDNLabel'
    $FQDNLabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $SecondLvl_Size)
    $FQDNLabel.Font = (New-Object -TypeName System.Drawing.Font -ArgumentList $SecondLvl_Font)
    $FQDNLabel.add_Click($FQDNLabel_Click)
    #endregion FQDN
    #region IP
    $IPLabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $FirstLvl_X_Loc, $IPLabel_Y_Loc)
    $IPLabel.Name = [System.String]'IPLabel'
    $IPLabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $FirstLvl_Size)
    $IPLabel.Font = (New-Object -TypeName System.Drawing.Font -ArgumentList $FirstLvl_Font)
    $IPLabel.add_Click($IPLabel_Click)

    $AutoCopyIP.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $AutoCopyIP_X_Loc, $IPLabel_Y_Loc)
    $AutoCopyIP.Name = [System.String]'AutoCopyIP'
    $AutoCopyIP.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $AutoCopyIP_Size)
    $AutoCopyIP.Text = [System.String]'Auto Copy IP'
    $AutoCopyIP.Checked = $true
    #endregion IP
    $UptimeLabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $FirstLvl_X_Loc, $UptimeLabel_Y_Loc)
    $UptimeLabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $FirstLvl_Size)
    $UptimeLabel.Font = (New-Object -TypeName System.Drawing.Font -ArgumentList $FirstLvl_Font)
    $UptimeLabel.AutoSize = $true
    #region Comp OU
    $CmpOULabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $SecondLvl_X_Loc, $CmpOULabel_Y_Loc)
    $CmpOULabel.Name = [System.String]'CmpOULabel'
    $CmpOULabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $OU_Size)
    $CmpOULabel.Font = (New-Object -TypeName System.Drawing.Font -ArgumentList $SecondLvl_Font)
    #endregion Comp OU
    #Region User Info
    $NameLabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $FirstLvl_X_Loc, $NameLabel_Y_Loc)
    $NameLabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $FirstLvl_Size)
    $NameLabel.Font = (New-Object -TypeName System.Drawing.Font -ArgumentList $FirstLvl_Font)
            
    $UsernameLabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $FirstLvl_X_Loc, $UsernameLabel_Y_Loc)
    $UsernameLabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $FirstLvl_Size)
    $UsernameLabel.Font = (New-Object -TypeName System.Drawing.Font -ArgumentList $FirstLvl_Font)
    $UsernameLabel.add_Click($UsernameLabel_Click)

    $ADButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $ADButton_X_Loc, $UsernameLabel_Y_Loc)
    $ADButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $ADButton_Size)
    $ADButton.Text = [System.String]'AD Profile'
    $ADButton.Name = [System.String]'ADButton'
    $ADButton.add_Click($ADButton_Click)



    $LockedLabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $FirstLvl_X_Loc, $LockedLabel_Y_Loc)
    $LockedLabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $FirstLvl_Size)
    $LockedLabel.Font = (New-Object -TypeName System.Drawing.Font -ArgumentList $FirstLvl_Font)

    $UnlockButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $UnlockButton_X_Loc, $LockedLabel_Y_Loc)
    $UnlockButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $UnlockButton_Size)
    $UnlockButton.Text = [System.String]'Unlock Acct'
    $UnlockButton.Name = [System.String]'UnlockButton'
    $UnlockButton.add_Click($UnlockButton_Click)

    $OpenLockoutStatus.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $OpenLockoutStatus_X_Loc, $OpenLockoutStatus_Y_Loc)
    $OpenLockoutStatus.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $OpenLockoutStatus_Size)
    $OpenLockoutStatus.Text = [System.String]'Open Lockout Status'
    $OpenLockoutStatus.Name = [System.String]'OpenLockoutStatus'
    $OpenLockoutStatus.add_Click($OpenLockoutStatus_Click)
    $OpenLockoutStatus.AutoSize = $true
            
    $UserOULabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $SecondLvl_X_Loc, $UserOULabel_Y_Loc)
    $UserOULabel.Name = [System.String]'UserOULabel'
    $UserOULabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $OU_Size)
    $UserOULabel.Font = (New-Object -TypeName System.Drawing.Font -ArgumentList $SecondLvl_Font)
            
    $SoftwareButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $SoftwareButton_X_Loc, $SoftwareButton_Y_Loc)
    $SoftwareButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $SoftwareButton_Size)
    $SoftwareButton.Text = [System.String]'Open Software Folder'
    $SoftwareButton.Name = [System.String]'SoftwareButton'
    $SoftwareButton.add_Click($SoftwareButton_Click)
    $SoftwareButton.Anchor = [System.Windows.Forms.AnchorStyles]([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right)
    #endregion User Info
    #endregion Results
    #endregion Form Properties

    #region Test Values

    #endregion Test Values

    #region Control Objects
    #region Properties
    $Min_Form_Size = @($SearchButton_Size[0] + $SearchButton_X_Loc + $btn_spacing)
    #endregion Properties
    #region Forms
    UpdateWindow -reset $true -cmp $true -user $true
    $Form1.ClientSize = (New-Object -TypeName System.Drawing.Size -ArgumentList $Form_Size)
    $Form1.Controls.Add($CmpBtn)
    $Form1.Controls.Add($UserBtn)
    $Form1.Controls.Add($SearchBox)
    $Form1.Controls.Add($SearchButton)
    $Form1.Controls.Add($EnforceNameLen)
    $Form1.Controls.Add($UserDropdown)
    $Form1.Controls.Add($CmpNumberLabel)
    $Form1.Controls.Add($OpenDriveButton)
    $Form1.Controls.Add($FQDNLabel)
    $Form1.Controls.Add($IPLabel)
    $Form1.Controls.Add($AutoCopyIP)
    $Form1.Controls.Add($CmpOULabel)
    $Form1.Controls.Add($NameLabel)
    $Form1.Controls.Add($UsernameLabel)
    # $Form1.Controls.Add($ADButton)
    $Form1.Controls.Add($UptimeLabel)
    $Form1.Controls.Add($LockedLabel)
    $Form1.Controls.Add($UnlockButton)
    $Form1.Controls.Add($OpenLockoutStatus)
    $Form1.Controls.Add($UserOULabel)
    $Form1.Controls.Add($SoftwareButton)
    $Form1.Text = [System.String]"Can Run Can't Hide"
    $Form1.MinimumSize = (New-Object -TypeName System.Drawing.Size -ArgumentList $Min_Form_Size)
    #endregion Forms
    $Form1.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
    $Form1.ResumeLayout($false)
    #endregion Control Objects
    #region Add-Members
    Add-Member -InputObject $Form1 -Name CmpBtn -Value $CmpBtn -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name UserBtn -Value $UserBtn -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name SearchBox -Value $SearchBox -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name SearchButton -Value $SearchButton -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name EnforceNameLen -Value $EnforceNameLen -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name UserDropdown -Value $UserDropdown -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name CmpNumberLabel -Value $CmpNumberLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name OpenDriveButton -Value $OpenDriveButton -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name FQDNLabel -Value $FQDNLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name IPLabel -Value $IPLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name AutoCopyIP -Value $AutoCopyIP -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name CmpOULabel -Value $CmpOULabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name NameLabel -Value $NameLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name UsernameLabel -Value $UsernameLabel -MemberType NoteProperty
    # Add-Member -InputObject $Form1 -Name ADButton -Value $ADButton -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name UptimeLabel -Value $UptimeLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name LockedLabel -Value $LockedLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name UnlockButton -Value $UnlockButton -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name OpenLockoutStatus -Value $OpenLockoutStatus -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name UserOULabel -Value $UserOULabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name SoftwareButton -Value $SoftwareButton -MemberType NoteProperty
    #endregion Add-Members
}
#endregion Add-Members
. InitializeComponent
$Form1.ShowDialog()




#region Ideas
# Auto Copy IP toggle
# Add button to open remote c drive
# Checkbox unicode [char]0x2713

# Open AD
# Open Lockout Status

#endregion Ideas
