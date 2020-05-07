# https://gist.github.com/darkfall/1656050
function ConvertTo-Icon
{
    <#
    .Synopsis
        Converts image to icons
    .Description
        Converts an image to an icon
    .Example
        ConvertTo-Icon -File .\Logo.png -OutputFile .\Favicon.ico
    #>
    [CmdletBinding()]
    param(
    # The file
    [Parameter(Mandatory=$true, Position=0,ValueFromPipelineByPropertyName=$true)]
    [Alias('Fullname')]
    [string]$File,
   
    # If provided, will output the icon to a location
    [Parameter(Position=1, ValueFromPipelineByPropertyName=$true)]
    [string]$OutputFile
    )
    
    begin {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing   
    }
    
    process {
        #region Load Icon
        $resolvedFile = $ExecutionContext.SessionState.Path.GetResolvedPSPathFromPSPath($file)
        if (-not $resolvedFile) { return }
        $inputBitmap = [Drawing.Image]::FromFile($resolvedFile)
        $width = $inputBitmap.Width
        $height = $inputBitmap.Height
        $size = New-Object Drawing.Size $width, $height
        $newBitmap = New-Object Drawing.Bitmap $inputBitmap, $size
        #endregion Load Icon

        #region Save Icon                     
        $memoryStream = New-Object System.IO.MemoryStream
        $newBitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)

        $resolvedOutputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($outputFile)
        $output = [IO.File]::Create("$resolvedOutputFile")
        
        $iconWriter = New-Object System.IO.BinaryWriter($output)
        # 0-1 reserved, 0
        $iconWriter.Write([byte]0)
        $iconWriter.Write([byte]0)

        # 2-3 image type, 1 = icon, 2 = cursor
        $iconWriter.Write([short]1);

        # 4-5 number of images
        $iconWriter.Write([short]1);

        # image entry 1
        # 0 image width
        $iconWriter.Write([byte]$width);
        # 1 image height
        $iconWriter.Write([byte]$height);

        # 2 number of colors
        $iconWriter.Write([byte]0);

        # 3 reserved
        $iconWriter.Write([byte]0);

        # 4-5 color planes
        $iconWriter.Write([short]0);

        # 6-7 bits per pixel
        $iconWriter.Write([short]32);

        # 8-11 size of image data
        $iconWriter.Write([int]$memoryStream.Length);

        # 12-15 offset of image data
        $iconWriter.Write([int](6 + 16));

        # write image data
        # png data must contain the whole png data file
        $iconWriter.Write($memoryStream.ToArray());

        $iconWriter.Flush();
        $output.Close()               
        #endregion Save Icon

        #region Cleanup
        $memoryStream.Dispose()
        $newBitmap.Dispose()
        $inputBitmap.Dispose()
        #endregion Cleanup
    }
}

function GetProgramFilesFolder {
    $folder = (Get-ChildItem "$Env:ProgramFiles\WindowsApps" | Where-Object { $_.Name -like "Microsoft.WindowsTerminal_*" } | Select-Object -First 1)
    return $folder.FullName
}

function GetWindowsTerminalIcon(
    [Parameter(Mandatory=$true)]
    [string]$folder,
    [Parameter(Mandatory=$true)]
    [string]$localCache)
{
    $actual = $folder + "\WindowsTerminal.exe"
    if (Test-Path $actual) {
        # use app icon directly.
        Write-Host "Found actual executable" $actual
        $icon = $actual
    } else {
        # download from GitHub
        Write-Warning "Didn't find actual executable $actual so download icon from GitHub."
        $icon = "$localCache\wt.ico"
        Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/microsoft/terminal/master/res/terminal.ico" -OutFile $icon
    }

    return $icon
}

function GetActiveProfiles {
    $settings = Get-Content "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" | Out-String | ConvertFrom-Json
    if ($settings.profiles.PSObject.Properties.name -match "list") {
        $list = $settings.profiles.list
    } else {
        $list = $settings.profiles 
    }

    return $list | Where-Object { -not $_.hidden} | Where-Object { ($null -eq $_.source) -or -not ($settings.disabledProfileSources -contains $_.source) }
}

function GetProfileIcon (
    [Parameter(Mandatory=$true)]
    $profile,
    [Parameter(Mandatory=$true)]
    [string]$folder,
    [Parameter(Mandatory=$true)]
    [string]$localCache,
    [Parameter(Mandatory=$true)]
    [string]$icon)
{
    $guid = $profile.guid
    $name = $profile.name
    $profileIcon = $null
    $profilePng = $null
    if ($null -ne $profile.icon) {
        if (Test-Path $profile.icon) {
            # use user setting
            $profilePng = $profile.icon  
        } elseif ($profile.icon -like "ms-appdata:///Roaming/*") {
            #resolve roaming cache
            $profilePng = $profile.icon -replace "ms-appdata:///Roaming", "$Env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\RoamingState" -replace "/", "\"
        } elseif ($profile.icon -like "ms-appdata:///Local/*") {
            #resolve local cache
            $profilePng = $profile.icon -replace "ms-appdata:///Local", "$Env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState" -replace "/", "\"
        } elseif ($profile.icon -like "ms-appx:///*") {
            # resolve app cache
            $profilePng = $profile.icon -replace "ms-appx://", $folder -replace "/", "\"
        } else {
            Write-Host "Invalid profile icon found" $profile.icon ". Please report an issue at https://github.com/lextm/windowsterminal-shell/issues ."
        }
    }

    if (($null -eq $profilePng) -or -not (Test-Path $profilePng)) {
        # fallback to profile PNG
        $profilePng = "$folder\ProfileIcons\$guid.scale-200.png"
    }

    if (Test-Path $profilePng) {
        if ($profilePng -like "*.png") {
            # found PNG, convert to ICO
            if (-not (Test-Path $localCache)) {
                New-Item $localCache -ItemType Directory | Out-Null
            }

            $profileIcon = "$localCache\$guid.ico"
            ConvertTo-Icon -File $profilePng -OutputFile $profileIcon
        } elseif ($profilePng -like "*.ico") {
            $profileIcon = $profilePng
        } else {
            Write-Warning "Icon format is not supported by this script" $profilePng ". Please use PNG or ICO format."
        }
    } else {
        Write-Warning "Didn't find icon for profile $name ."
    }

    if ($null -eq $profileIcon) {
        # final fallback
        $profileIcon = $icon
    }

    return $profileIcon
}

function CreateProfileMenuItem(
    [Parameter(Mandatory=$true)]
    $profile,
    [Parameter(Mandatory=$true)]
    [string]$executable,
    [Parameter(Mandatory=$true)]
    [string]$folder,
    [Parameter(Mandatory=$true)]
    [string]$localCache,
    [Parameter(Mandatory=$true)]
    [string]$icon)
{
    $guid = $profile.guid
    $name = $profile.name
    if ($profile.commandline -match '(?<commandline>.+\.exe)(\s+.*)?') {
        $commandline = $Matches.commandline
    } else {
        $commandline = $null
    }

    $command = "$executable -p ""$name"" -d ""%V."""
    $elevated1 = "PowerShell -WindowStyle Hidden -Command ""Start-Process PowerShell.exe -WindowStyle Hidden -Verb RunAs -ArgumentList """"-Command $executable -d `"%V.`" -p `"$name`""""""""
    $elevated2 = "PowerShell -WindowStyle Hidden -Command ""Start-Process cmd.exe -WindowStyle Hidden -Verb RunAs -ArgumentList \""/c ""$executable -p ""$name"" -d ""%V.""\"" """
    if ($commandline -eq "cmd.exe") {
        $elevated = $elevated2
    } else {
        $elevated = $elevated1
    }

    $profileIcon = GetProfileIcon $profile $folder $localCache $icon
    New-Item -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminal\shell\$guid" -Force | Out-Null
    New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminal\shell\$guid" -Name 'MUIVerb' -PropertyType String -Value $name | Out-Null
    New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminal\shell\$guid" -Name 'Icon' -PropertyType String -Value $profileIcon | Out-Null
    
    New-Item -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminal\shell\$guid\command" -Force | Out-Null
    New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminal\shell\$guid\command" -Name '(Default)' -PropertyType String -Value $command | Out-Null

    New-Item -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminalAdmin\shell\$guid" -Force | Out-Null
    New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminalAdmin\shell\$guid" -Name 'MUIVerb' -PropertyType String -Value $name | Out-Null
    New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminalAdmin\shell\$guid" -Name 'Icon' -PropertyType String -Value $profileIcon | Out-Null
    New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminalAdmin\shell\$guid" -Name 'HasLUAShield' -PropertyType String -Value '' | Out-Null
    
    New-Item -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminalAdmin\shell\$guid\command" -Force | Out-Null
    New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminalAdmin\shell\$guid\command" -Name '(Default)' -PropertyType String -Value $elevated | Out-Null
}

function CreateMenuItems(
    [Parameter(Mandatory=$true)]
    $executable)
{
    $folder = GetProgramFilesFolder
    $localCache = "$Env:LOCALAPPDATA\Microsoft\WindowsApps\Cache"
    $icon = GetWindowsTerminalIcon $folder $localCache

    New-Item -Path 'Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\MenuTerminal' -Force | Out-Null
    New-ItemProperty -Path 'Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\MenuTerminal' -Name 'MUIVerb' -PropertyType String -Value 'Windows Terminal here' | Out-Null
    New-ItemProperty -Path 'Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\MenuTerminal' -Name 'Icon' -PropertyType String -Value $icon | Out-Null
    New-ItemProperty -Path 'Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\MenuTerminal' -Name 'ExtendedSubCommandsKey' -PropertyType String -Value 'Directory\\ContextMenus\\MenuTerminal' | Out-Null

    New-Item -Path 'Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminal\shell' -Force | Out-Null

    New-Item -Path 'Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\MenuTerminalAdmin' -Force | Out-Null
    New-ItemProperty -Path 'Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\MenuTerminalAdmin' -Name 'MUIVerb' -PropertyType String -Value 'Windows Terminal (Admin) here' | Out-Null
    New-ItemProperty -Path 'Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\MenuTerminalAdmin' -Name 'Icon' -PropertyType String -Value $icon | Out-Null
    New-ItemProperty -Path 'Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\MenuTerminalAdmin' -Name 'ExtendedSubCommandsKey' -PropertyType String -Value 'Directory\\ContextMenus\\MenuTerminalAdmin' | Out-Null

    New-Item -Path 'Registry::HKEY_CLASSES_ROOT\Directory\ContextMenus\MenuTerminalAdmin\shell' -Force | Out-Null

    $profiles = GetActiveProfiles
    foreach ($profile in $profiles) {
        CreateProfileMenuItem $profile $executable $folder $localCache $icon
    }
}

# Based on @nerdio01's version in https://github.com/microsoft/terminal/issues/1060

if ($PSVersionTable.PSVersion.Major -lt 6) {
    Write-Error "Must be executed in PowerShell 6 and above. Learn how to install it from https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows?view=powershell-7 . Exit."
    exit 1
}

$executable = "$Env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
if (-not (Test-Path $executable)) {
    Write-Error "Windows Terminal not detected. Learn how to install it from https://github.com/microsoft/terminal . Exit."
    exit 1
}

CreateMenuItems $executable



Write-Host "Windows Terminal installed to Windows Explorer context menu."
