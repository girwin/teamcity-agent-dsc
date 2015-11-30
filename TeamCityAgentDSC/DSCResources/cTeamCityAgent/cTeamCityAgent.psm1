function Get-TargetResource
{
    [OutputType([Hashtable])]
    param (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AgentName,
        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",
        [string]$AgentHomeDirectory,
        [string]$AgentWorkDirectory,
        [string]$AgentHostname,
        [int]$AgentPort,
        [string]$ServerHostname,
        [int]$ServerPort,
        [string]$AgentBuildParameters
    )

    Write-Verbose "Checking if TeamCity Agent is installed"
    $installLocation = (get-itemproperty -path "HKLM:\Software\ORACLE\KEY_XE" -ErrorAction SilentlyContinue).ORACLE_HOME
    $present = Test-Path "$AgentHomeDirectory\bin\service.start.bat"
    Write-Verbose "TeamCity Agent present: $present"

    $currentEnsure = if ($present) { "Present" } else { "Absent" }

    $serviceName = Get-TeamCityAgentServiceName -AgentName $AgentName
    Write-Verbose "Checking for Windows Service: $serviceName"
    $serviceInstance = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    $currentState = "Stopped"
    if ($serviceInstance -ne $null)
    {
        Write-Verbose "Windows service: $($serviceInstance.Status)"
        if ($serviceInstance.Status -eq "Running")
        {
            $currentState = "Started"
        }

        if ($currentEnsure -eq "Absent")
        {
            Write-Verbose "Since the Windows Service is still installed, the service is present"
            $currentEnsure = "Present"
        }
    }
    else
    {
        Write-Verbose "Windows service: Not installed"
        $currentEnsure = "Absent"
    }

    return @{
        AgentName = $AgentName;
        Ensure = $currentEnsure;
        State = $currentState;
    };
}

function Set-TargetResource
{
    param (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AgentName,
        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",
        [string]$AgentHomeDirectory = "C:\TeamCity\Agent",
        [string]$AgentWorkDirectory = "C:\TeamCity\Agent\work",
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AgentHostname,
        [Parameter(Mandatory)]
        [int]$AgentPort,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerHostname,
        [Parameter(Mandatory)]
        [int]$ServerPort,
        [string]$AgentBuildParameters
    )

    if ($Ensure -eq "Absent" -and $State -eq "Started")
    {
        throw "Invalid configuration: service cannot be both 'Absent' and 'Started'"
    }

    $currentResource = (Get-TargetResource -AgentName $AgentName -AgentHomeDirectory $AgentHomeDirectory)

    Write-Verbose "Configuring TeamCity Agent ..."

    $serviceName = Get-TeamCityAgentServiceName -AgentName $AgentName

    if ($State -eq "Stopped" -and $currentResource["State"] -eq "Started")
    {
        Write-Verbose "Stopping TeamCity Agent service $serviceName"
        Stop-Service -Name $serviceName -Force
    }

    if ($Ensure -eq "Absent" -and $currentResource["Ensure"] -eq "Present")
    {
        # Uninstall TeamCity Agent
        throw "Removal of TeamCity Agent Currently not supported by this DSC Module!"
    }
    elseif ($Ensure -eq "Present" -and $currentResource["Ensure"] -eq "Absent")
    {
        Write-Verbose "Installing TeamCity Agent..."
        Install-TeamCityAgent -AgentName $AgentName -AgentHomeDirectory $AgentHomeDirectory -AgentWorkDirectory $AgentWorkDirectory `
            -AgentHostname $AgentHostname -AgentPort $AgentPort -ServerHostname $ServerHostname -ServerPort $ServerPort `
            -AgentBuildParameters $AgentBuildParameters
        Write-Verbose "TeamCity Agent installed!"
    }

    if ($State -eq "Started" -and $currentResource["State"] -eq "Stopped")
    {
        Write-Verbose "Starting TeamCity Agent service $serviceName"
        Start-Service -Name $serviceName
    }

    Write-Verbose "Finished"
}

function Test-TargetResource
{
    param (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AgentName,
        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",
        [string]$AgentHomeDirectory,
        [string]$AgentWorkDirectory,
        [string]$AgentHostname,
        [int]$AgentPort,
        [string]$ServerHostname,
        [int]$ServerPort,
        [string]$AgentBuildParameters
    )

    $currentResource = (Get-TargetResource -AgentName $AgentName -AgentHomeDirectory $AgentHomeDirectory)

    $ensureMatch = $currentResource["Ensure"] -eq $Ensure
    Write-Verbose "Ensure: $($currentResource["Ensure"]) vs. $Ensure = $ensureMatch"
    if (!$ensureMatch)
    {
        return $false
    }

    $stateMatch = $currentResource["State"] -eq $State
    Write-Verbose "State: $($currentResource["State"]) vs. $State = $stateMatch"
    if (!$stateMatch)
    {
        return $false
    }

    return $true
}

function Get-TeamCityAgentServiceName {
    param (
        [string]$AgentName
    )
    #For now just using default TeamCity Agent Service Name
    return "TCBuildAgent"
}

function Request-File
{
    param (
        [string]$url,
        [string]$saveAs
    )

    Write-Verbose "Downloading $url to $saveAs"
    $downloader = new-object System.Net.WebClient
    $downloader.DownloadFile($url, $saveAs)
}

function Expand-ZipFile
{
    param (
        [string]$file,
        [string]$destination
    )
    Add-Type -assembly "system.io.compression.filesystem"
    [io.compression.zipfile]::ExtractToDirectory($file, $destination)
}

function Write-TokenReplacedFile {
    param(
        [parameter(Position=0)][string] $fileToTokenReplace,
        [parameter(position=1)][string] $outFile,
        [parameter(position=2)][hashtable] $tokenValues
    )
    $fileContents = Get-Content -Raw $fileToTokenReplace
    foreach ($token in $tokenValues.GetEnumerator()) {
        $fileContents = $fileContents -replace $token.Name, $token.Value
    }
    [io.file]::WriteAllText($outFile,$fileContents)
}

function Install-TeamCityAgent
{
    param (
        [Parameter(Mandatory)]
        [string]$AgentName,
        [Parameter(Mandatory=$True)]
        [string]$AgentHomeDirectory,
        [Parameter(Mandatory=$True)]
        [string]$AgentWorkDirectory,
        [Parameter(Mandatory=$True)]
        [string]$AgentHostname,
        [Parameter(Mandatory=$True)]
        [int]$AgentPort,
        [Parameter(Mandatory=$True)]
        [string]$ServerHostname,
        [Parameter(Mandatory=$True)]
        [int]$ServerPort,
        [string]$AgentBuildParameters
    )


    if ((test-path $AgentHomeDirectory) -ne $true) {
        New-Item $AgentHomeDirectory -type directory
    }

    $installationZipFilePath = "$AgentHomeDirectory\TeamCityAgent.zip"
    if ((test-path $installationZipFilePath) -ne $true)
    {
        $TeamCityAgentInstallationZipUrl = "http://$($ServerHostname):$($ServerPort)/update/buildAgent.zip"
        Write-Verbose "Downloading TeamCity Agent installation zip from $TeamCityAgentInstallationZipUrl to $installationZipFilePath"
        Request-File $TeamCityAgentInstallationZipUrl $installationZipFilePath
        Write-Verbose "Downloaded TeamCity Agent installation zip to $installationZipFilePath"
    }

    Write-Verbose "Expanding TeamCity Agent installation zip $installationZipFilePath to directory $AgentHomeDirectory"
    Expand-ZipFile $installationZipFilePath $AgentHomeDirectory
    Write-Verbose "Expanded TeamCity Agent installation zip to directory $AgentHomeDirectory"

    Write-Verbose "Configuring TeamCity Agent with name: $AgentName, ownAddress: $AgentHostname, ownPort: $AgentPort, server hostname: $ServerHostname, server port: $ServerPort."
    $teamCityConfigFile = "$AgentHomeDirectory\\conf\\buildAgent.properties"
    $AgentBuildParameterHashtable = convertfrom-stringdata -stringdata $AgentBuildParameters
    $agentBuildParametersString = ''
    $AgentBuildParameterHashtable.Keys | % { $agentBuildParametersString += "`n$($_)=$($AgentBuildParameterHashtable.Item($_))" }

    Write-TokenReplacedFile "$AgentHomeDirectory\\conf\\buildAgent.dist.properties" $teamCityConfigFile @{
       'serverUrl=http://localhost:8111/' = "serverUrl=http://$($ServerHostname):$($ServerPort)";
       'name=' = "name=$AgentName";
       'ownPort=9090' = "ownPort=$AgentPort";
       '#ownAddress=<own IP address or server-accessible domain name>' = "ownAddress=$AgentHostname";
       'workDir=../work' = "workDir=$AgentWorkDirectory";
       '#env.exampleEnvVar=example Env Value' = $agentBuildParametersString;
    }

    Write-Verbose "Configured TeamCity Agent in file $teamCityConfigFile"

    $serviceName = Get-TeamCityAgentServiceName -AgentName $AgentName
    Write-Verbose "Installing TeamCity Agent Windows service with name $serviceName ..."
    Push-Location -Path "$AgentHomeDirectory\bin"
    .\service.install.bat
    Pop-Location
    Write-Verbose "Installed TeamCity Agent Windows service with name $serviceName."

}
