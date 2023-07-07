#Created by: Aaron Rosenberg, 2023
using assembly System.Windows.Forms
using namespace System.Windows.Forms
using namespace System.Drawing
#https://stackoverflow.com/questions/60175542/powershell-textbox-placeholder
$assemblies = "System.Windows.Forms", "System.Drawing"
$code = @"
using System.Drawing;
using System.Windows.Forms;
public class ExRichTextBox : RichTextBox
{
    string hint;
    public string Hint
    {
        get { return hint; }
        set { hint = value; this.Invalidate(); }
    }
    protected override void WndProc(ref Message m)
    {
        base.WndProc(ref m);
        if (m.Msg == 0xf)
        {
            if (!this.Focused && string.IsNullOrEmpty(this.Text)
                && !string.IsNullOrEmpty(this.Hint))
            {
                using (var g = this.CreateGraphics())
                {
                    TextRenderer.DrawText(g, this.Hint, this.Font,
                        this.ClientRectangle, SystemColors.GrayText , this.BackColor, 
                        TextFormatFlags.Top | TextFormatFlags.Left);
                }
            }
        }
    }
}
"@
Add-Type -ReferencedAssemblies $assemblies -TypeDefinition $code -Language CSharp  
Add-Type -AssemblyName System.Windows.Forms
$Form1 = New-Object -TypeName System.Windows.Forms.Form
$ADList = @("example1.dom", "example2.dom", "example3.dom")
$global:userData = @{}

#region Declaration
[System.Windows.Forms.RadioButton]$CmpBtn = $null
[System.Windows.Forms.RadioButton]$UserBtn = $null

[ExRichTextBox]$SearchBox = $null # Renamed from $PCNameInput
[System.Windows.Forms.Button]$SearchButton = $null
[System.Windows.Forms.CheckBox]$EnforceNameLen = $null
[System.Windows.Forms.ComboBox]$UserDropdown = $null
[System.Windows.Forms.LinkLabel]$CmpNumberLabel = $null
[System.Windows.Forms.Button]$OpenDriveButton = $null   
[System.Windows.Forms.LinkLabel]$FQDNLabel = $null
[System.Windows.Forms.Button]$MRCButton = $null
[System.Windows.Forms.LinkLabel]$IPLabel = $null
[System.Windows.Forms.CheckBox]$AutoCopyIP = $null
[System.Windows.Forms.Label]$CmpOULabel = $null
[System.Windows.Forms.Label]$NameLabel = $null
[System.Windows.Forms.LinkLabel]$UsernameLabel = $null
[System.Windows.Forms.Button]$DeployFixButton = $null
[System.Windows.Forms.Label]$UptimeLabel = $null
[System.Windows.Forms.Label]$LockedLabel = $null
[System.Windows.Forms.Button]$UnlockButton = $null
[System.Windows.Forms.LinkLabel]$OpenLockoutStatus = $null
[System.Windows.Forms.Label]$UserOULabel = $null
[System.Windows.Forms.Button]$SoftwareButton = $null
[System.Windows.Forms.ToolTip]$ToolTipMain = $null
[System.ComponentModel.IContainer]$components = $null


#endregion Declartion


#region Listeners
$UserBtn_CheckedChanged = {
    $EnforceNameLen.Visible = $false
    $SearchBox.Hint = [System.String]'Enter Username'
}
$CmpBtn_CheckedChanged = {
    $EnforceNameLen.Visible = $true
    $SearchBox.Hint = [System.String]'Enter Computer Name'

}
$SearchButton_Click = {
    # $Global:verifCmpNum = $null
    SearchForPC
}
$SearchBox_EnterPressed = {
    if ($_.KeyCode -eq 'Enter') {
    SearchForPC
    }
}
    #endregion Computer Search
$OpenDriveButton_Click = {
    if ($null -eq $global:userData['pcNum']) {
        PopupMsg "No PC Selected" -msgTitle "No PC Selected" -iconType 16
        return
    }
    Invoke-Item -Path ("\\" + $global:userData['pcNum'] + "\c$") #change to $pcName when implemented
}

$MRCButton_Click = {
    #https://documentation.solarwinds.com/en/success_center/dameware/content/cli_functionality.htm
    if ($null -eq $global:userData['pcNum']) {
        PopupMsg "No PC Selected" -msgTitle "No PC Selected" -iconType 16
    }
    try{try {
        & 'C:\Program Files\SolarWinds\DameWare Mini Remote Control x64\DWRCC.exe' -c: -h: -a:1 -m:$global:userData['IP']
    }catch{
        & 'C:\Program Files\SolarWinds\DameWare Mini Remote Control x64 #1\DWRCC.exe' -c: -h: -a:1 -m:$global:userData['IP'] # server 7 has messed up dameware folder
    }}
    catch {
        PopupMsg "Unable to open MRC" -msgTitle "Unable to open MRC" -iconType 16
    }
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
$DeployFixButton_Click = { DeployFix }
$UnlockButton_Click = { UnlockUser $global:userData['username']}
$OpenLockoutStatus_Click = {
    try{
        $fullName = $global:userData['username'] + "@" + $global:userData['server']
        C:\Software\LockoutStatus.exe -u:$fullName
    }catch{PopupMsg "Unable to Open LockoutStatus" -msgTitle "Unable to Open LockoutStatus" -iconType 16}
}
$SoftwareButton_Click = { Invoke-Item -path "{NETWORK SOFTWARE FOLDER}"}
$ConsoleButton_Click = {}
#region Functions
$DeployFixButton_ToolTip = [System.String]'Deploys the selected fix to the selected PC' #UPDATE: on fix change
function DeployFix { # Remember to change Tooltip and Button Text when the fix changes
    try {
        $tokenBroker = Get-WmiObject -Class Win32_Service -ComputerName $cmpName -Filter "Name='TokenBroker'"
        $clickToRun = Get-WmiObject -Class Win32_Service -ComputerName $cmpName -Filter "Name='ClickToRunSvc'"
        $tokenBroker.StopService()
        $clickToRun.StopService()
        Set-Location \\$cmpName\c$\users\$userName\appdata\local\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker\Accounts
        Remove-Item -force -recurse *
        Set-Location \\$cmpName\c$\users\$userName\appdata\local\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\Settings
        Set-Location \\$cmpName\c$\users\$userName\appdata\local\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\Settings
        Rename-Item -Path settings.dat -NewName settings.dat.bak
        $tokenBroker.StartService()
        $clickToRun.StartService()
        PopupMsg "Fix Deployed" -msgTitle "Fix Deployed" -iconType 64
    }
    catch {
        PopupMsg "Unable to Deploy Fix" -msgTitle "Unable to Deploy Fix" -iconType 16
    }
}
function SearchForPC {
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
            $passwordServers = Get-ADGroupMember -server $global:userData['server'] "Domain Controllers" | Select-Object -ExpandProperty Name
            $unsuccessUnlocks = @()
            foreach ($server in $passwordServers){
                Try{
                    Unlock-ADAccount $user -server $server -ErrorAction SilentlyContinue
                }catch{
                    $unsuccessUnlocks += $server
                }
            }
            if ($unsuccessUnlocks.length -gt 0){
                $failedStr = [String]::Join("`n", $unsuccessUnlocks)
                PopupMsg $failedStr -msgTitle "Unlock Unsuccessful On:"
            }else{
                PopupMsg "Unlock Successful" -msgTitle "Unlock Successful" -iconType 64
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
                PopupMsg "Please Select User From Dropdown" -msgTitle "Multiple Users" -iconType 64
            }
    }catch {
        PopupMsg -Message "Cannot Get Users"
        UpdateWindow -reset $true -user $true
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
        @{}
    }
    #endregion Resources



    #region Instantiate Objects
    $components = (New-Object -TypeName System.ComponentModel.Container)
    $CmpBtn = (New-Object -TypeName System.Windows.Forms.RadioButton)
    $UserBtn = (New-Object -TypeName System.Windows.Forms.RadioButton)
    $SearchBox = (New-Object -TypeName ExRichTextBox)
    $SearchButton = (New-Object -TypeName System.Windows.Forms.Button)
    $EnforceNameLen = (New-Object -TypeName System.Windows.Forms.CheckBox)
    $UserDropdown = (New-Object -TypeName System.Windows.Forms.ComboBox)
    $CmpNumberLabel = (New-Object -TypeName System.Windows.Forms.LinkLabel)
    $OpenDriveButton = (New-Object -TypeName System.Windows.Forms.Button)
    $FQDNLabel = (New-Object -TypeName System.Windows.Forms.LinkLabel)
    $MRCButton = (New-Object -TypeName System.Windows.Forms.Button)
    $IPLabel = (New-Object -TypeName System.Windows.Forms.LinkLabel)
    $AutoCopyIP = (New-Object -TypeName System.Windows.Forms.CheckBox)
    $CmpOULabel = (New-Object -TypeName System.Windows.Forms.Label)
    $NameLabel = (New-Object -TypeName System.Windows.Forms.Label)
    $UsernameLabel = (New-Object -TypeName System.Windows.Forms.LinkLabel)
    $DeployFixButton = (New-Object -TypeName System.Windows.Forms.Button)
    $UptimeLabel = (New-Object -TypeName System.Windows.Forms.Label)
    $LockedLabel = (New-Object -TypeName System.Windows.Forms.Label)
    $UnlockButton = (New-Object -TypeName System.Windows.Forms.Button)
    $OpenLockoutStatus = (New-Object -TypeName System.Windows.Forms.LinkLabel)
    $UserOULabel = (New-Object -TypeName System.Windows.Forms.Label)
    $SoftwareButton = (New-Object -TypeName System.Windows.Forms.Button)
    $ToolTipMain = (New-Object -TypeName System.Windows.Forms.ToolTip -ArgumentList @($components))

    

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
    $DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
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
    $SearchBox.Hint = [System.String]'Enter Computer Name'
    $SearchBox.Multiline = $false
    $SearchBox.add_KeyDown($SearchBox_EnterPressed)

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
    $UserDropdown.DropDownStyle = $DropDownStyle
    $UserDropdown.add_SelectedIndexChanged($UserDropdown_SelectedIndexChanged)
    #endregion User Dropdown
    #endregion Search
    #region Results
    #region Properties
    $FirstLvl_Font = @([System.String]'Tahoma', [System.Single]12)
    $SecondLvl_Font = @([System.String]'Tahoma', [System.Single]8)

    $AutoCopyIP_Size = @(100, 20)
    $OU_Size = @(250, 40)
    $DeployFixButton_Size = @(100, 40)
    $UnlockButton_Size = @(100, 20)
    $OpenLockoutStatus_Size = @(100, 20)
    $FirstLvl_Size = @(300, 20)
    $SecondLvl_Size = @(250, 20)
    $OpenDriveButton_Size = @(100, 20)
    $SoftwareButton_Size = @(150, 20)
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
    $DeployFixButton_X_Loc = $Form_Size[0] - $DeployFixButton_Size[0] - $FirstLvl_X_Loc
    $LockedLabel_Y_Loc = $UsernameLabel_Y_Loc + $FirstLvl_Size[1] + $btn_spacing
    $UnlockButton_X_Loc = $Form_Size[0] - $UnlockButton_Size[0] - $FirstLvl_X_Loc
    $OpenLockoutStatus_X_Loc = $Form_Size[0] - $OpenLockoutStatus_Size[0] - $FirstLvl_X_Loc 
    $OpenLockoutStatus_Y_Loc = $LockedLabel_Y_Loc + $UnlockButton_Size[1] + $btn_spacing
    $UserOULabel_Y_Loc = $LockedLabel_Y_Loc + $FirstLvl_Size[1] + $btn_spacing
    $SoftwareButton_X_Loc = $Form_Size[0] - $SoftwareButton_Size[0] - $FirstLvl_X_Loc
    $SoftwareButton_Y_Loc = $Form_Size[1] - $SoftwareButton_Size[1] - $btn_spacing

    $currentFixName = [System.String]'M365 TokenBroker Fix'
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
    #MRC Button
    $MRCButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]$OpenDriveButton_X_Loc, [System.Int32]$FQDNLabel_Y_Loc))
    $MRCButton.Name = [System.String]'MRCButton'
    $MRCButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $OpenDriveButton_Size)
    $MRCButton.Text = [System.String]'Remote Into'
    $MRCButton.add_Click($MRCButton_Click)
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

    $DeployFixButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList $DeployFixButton_X_Loc, $NameLabel_Y_Loc)
    $DeployFixButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList $DeployFixButton_Size)
    $DeployFixButton.Text = $currentFixName
    $DeployFixButton.Name = [System.String]'DeployFixButton'
    $DeployFixButton.add_Click($DeployFixButton_Click)



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
    $SoftwareButton.Text = [System.String]'Open ServiceDesk Folder'
    $SoftwareButton.Name = [System.String]'SoftwareButton'
    $SoftwareButton.add_Click($SoftwareButton_Click)
    $SoftwareButton.Anchor = [System.Windows.Forms.AnchorStyles]([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right)
    #endregion User Info
    #endregion Results
    #endregion Form Properties
    #region Tooltips
    $EnforceNameLength_ToolTip = [System.String]"Enforce a 10 Char length for the PC name"
    $OpenDriveButton_ToolTip = [System.String]"Open the selected PC's C: drive in Explorer"
    $MRCButton_ToolTip = [System.String]'Remote into the Selected PC'
    $AutoCopyIP_ToolTip = [System.String]"Automatically copy the IP address `nto the clipboard when a PC is searched for"
    $UnlockButton_ToolTip = [System.String]'Attempts to Unlock the selected user account through AD'
    $OpenLockoutStatus_ToolTip = [System.String]'Opens a Lockout Status window with the selected user account'
    $SoftwareButton_ToolTip = [System.String]'Opens the Network ServiceDesk Folder'
    $ToolTips = @()
    # foreach($tooltip in $ToolTips){
    #     if $tooltip.length -gt 40{}
    # }
    $ToolTipMain.SetToolTip($MRCButton, $MRCButton_ToolTip)
    $ToolTipMain.SetToolTip($AutoCopyIP, $AutoCopyIP_ToolTip)
    $ToolTipMain.SetToolTip($EnforceNameLen, $EnforceNameLength_ToolTip)
    $ToolTipMain.SetToolTip($OpenDriveButton, $OpenDriveButton_ToolTip)
    $ToolTipMain.SetToolTip($UnlockButton, $UnlockButton_ToolTip)
    $ToolTipMain.SetToolTip($OpenLockoutStatus, $OpenLockoutStatus_ToolTip)
    $ToolTipMain.SetToolTip($SoftwareButton, $SoftwareButton_ToolTip)
    $ToolTipMain.SetToolTip($DeployFixButton, $DeployFixButton_ToolTip)

    #endregion Tooltips
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
    $Form1.Controls.Add($MRCButton)
    $Form1.Controls.Add($IPLabel)
    $Form1.Controls.Add($AutoCopyIP)
    $Form1.Controls.Add($CmpOULabel)
    $Form1.Controls.Add($NameLabel)
    $Form1.Controls.Add($UsernameLabel)
    $Form1.Controls.Add($DeployFixButton)
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
    Add-Member -InputObject $Form1 -Name MRCButton -Value $MRCButton -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name IPLabel -Value $IPLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name AutoCopyIP -Value $AutoCopyIP -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name CmpOULabel -Value $CmpOULabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name NameLabel -Value $NameLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name UsernameLabel -Value $UsernameLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name DeployFixButton -Value $DeployFixButton -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name UptimeLabel -Value $UptimeLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name LockedLabel -Value $LockedLabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name UnlockButton -Value $UnlockButton -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name OpenLockoutStatus -Value $OpenLockoutStatus -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name UserOULabel -Value $UserOULabel -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name SoftwareButton -Value $SoftwareButton -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name ToolTipMain -Value $ToolTipMain -MemberType NoteProperty
    Add-Member -InputObject $Form1 -Name components -Value $components -MemberType NoteProperty

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
