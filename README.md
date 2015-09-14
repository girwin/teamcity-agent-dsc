This repository contains a PowerShell module with a DSC resource that can be used to install TeamCity Agent

## Sample

First, ensure the TeamCityAgentDSC module is on your `$env:PSModulePath`. Then you can create and apply configuration like this.

```
Configuration SampleConfig
{
    Import-DscResource -Module TeamCityAgentDSC
 
    Node "localhost"
    {
        cTeamCityAgent TeamCityAgent 
        { 
            Ensure = "Present" 
            State = "Started"         
            AgentName = "TeamCity Build Agent"             
            ServerHostname = "the public hostname or ip of your teamcity server;
            AgentHomeDirectory = 'C:\TeamCity\Agent';
            AgentWorkDirectory = 'F:\TeamCity\Agent\work';    
        }
    }
}
 
SampleConfig 

Start-DscConfiguration .\SampleConfig -Verbose -wait

Test-DscConfiguration
```

## Settings

When `Ensure` is set to `Present`, the resource will:

 1. Download the TeamCity Agent Zip from the TeamCity Server
 2. Install and configure TeamCity Agent
 3. Setup TeamCity Agent as a Windows Service 

When `Ensure` is set to `Absent`, the resource will throw an error as uninstall of TeamCity Agent is not supported by module yet.

When `State` is `Started`, the resource will ensure that the TeamCity Agent windows service 'TeamCityAgent' is running. When `Stopped`, it will ensure the service is st opped.


