#requires -version 5.1
$ErrorActionPreference='Stop'
$native='C:\Program Files\VMware\VMware Workstation\vmware.exe'
$legacy='C:\Program Files (x86)\VMware\VMware Workstation\vmware.exe'
$script:fixtures=@{}
function Test-Path { param($LiteralPath,$PathType) return $script:fixtures.ContainsKey($LiteralPath) }
function Get-Item { param($LiteralPath,$ErrorAction) return [pscustomobject]@{VersionInfo=[pscustomobject]@{ProductName=$script:fixtures[$LiteralPath]}} }
function Assert($Condition,[string]$Message){ if(-not $Condition){ throw $Message }; Write-Host "PASS: $Message" }
foreach($file in @('Install-TypeB.ps1','Initialize-TypeBUser.ps1')){
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime') $file),[ref]$tokens,[ref]$errors)
    if($errors.Count){ throw ($errors | Out-String) }
    $resolver=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-TypeBVmwareExecutable'},$false)
    if(@($resolver).Count -ne 1){ throw 'Missing or duplicate resolver.' }
    Invoke-Expression $resolver.Extent.Text
    $script:fixtures=@{$native='VMware Workstation'}
    Assert ((Resolve-TypeBVmwareExecutable) -eq $native) "$file resolves native Program Files installation."
    $script:fixtures=@{$legacy='VMware Workstation'}
    Assert ((Resolve-TypeBVmwareExecutable) -eq $legacy) "$file preserves legacy Program Files (x86) support."
    $script:fixtures=@{}
    Assert ($null -eq (Resolve-TypeBVmwareExecutable)) "$file rejects missing installation."
    $script:fixtures=@{$native='Unrelated product'}
    Assert ($null -eq (Resolve-TypeBVmwareExecutable)) "$file rejects unrelated executable."
    $script:fixtures=@{$native='Unrelated product';$legacy='VMware Workstation'}
    Assert ((Resolve-TypeBVmwareExecutable) -eq $legacy) "$file falls back to valid legacy installation."
    $script:fixtures=@{$native='VMware Workstation';$legacy='VMware Workstation'}
    Assert ((Resolve-TypeBVmwareExecutable) -eq $native) "$file consistently prefers valid native installation."
    if($file -eq 'Install-TypeB.ps1'){
        $definition=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-Detection'},$false)
        Invoke-Expression $definition.Extent.Text
        Assert (Test-Detection ([pscustomobject]@{type='vmwareWorkstation'})) 'Runtime detection accepts installed native VMware.'
        $script:fixtures=@{}
        Assert (-not (Test-Detection ([pscustomobject]@{type='vmwareWorkstation'}))) 'Runtime detection does not fabricate PASS when VMware is absent.'
    } else {
        # Evaluate only the actual shortcut command from the initializer, with a
        # stub COM-free shortcut writer; never run WSL or copy a VM on the host.
        function Add-Shortcut([string]$Name,[string]$Target,[string]$Arguments){
            $script:shortcut=[pscustomobject]@{Name=$Name;Target=$Target;Arguments=$Arguments}
        }
        $command=$ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Shortcut'},$false) | Where-Object { $_.CommandElements[1].Value -eq 'Ubuntu 22.04 VM' }
        $vmwareExecutable=Resolve-TypeBVmwareExecutable
        $vmx='C:\Users\Example User\Virtual Machines\TypeB-Ubuntu-22.04\TypeB-Ubuntu-22.04.vmx'
        Invoke-Expression $command.Extent.Text
        Assert ($script:shortcut.Target -eq $native -and $script:shortcut.Arguments -eq ('-n "'+$vmx+'"')) 'Prepared Ubuntu shortcut uses the resolved executable and preserves quoted VMX path.'
    }
}
Write-Host 'VMware path checks: PASS. No installer or VMware application was executed.'
