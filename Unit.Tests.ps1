BeforeDiscovery {
    $expectedFunctions = @(
        "Get-TeslaApiToken",
        "Get-OctopusAgilePricing",
        "Get-TeslaProducts",
        "Get-TeslaEnergySiteId",
        "Get-TeslaPowerWallId",
        "Get-TeslaPowerWallStatus",
        "Set-TeslaEnergySiteReservePower",
        "Invoke-AgileBatteryControl"
    )

    $Rules = Get-ScriptAnalyzerRule

    $PsScriptAnalyzerSettings = 'PSScriptAnalyzerSettings.psd1'
    $Tests = $rules.ForEach{
        @{
            RuleName                 = $_.RuleName
            PsScriptAnalyzerSettings = $PsScriptAnalyzerSettings
        }
    }

    $scripts = Get-ChildItem -Include *.ps1, *.psm1, *.psd1 -Recurse | Where-Object FullName -NotMatch 'classes' | Where-Object FullName -NotMatch 'Tests.ps1'
}

BeforeAll { 

    $script:ModuleName = 'AgileBattery'

    Remove-Module $ModuleName -ErrorAction SilentlyContinue
    Import-Module ./AgileBattery.psd1

    $exportedFunctions = (Get-Command -Module $ModuleName).Name



}

Describe "AgileBattery module" {
    Context "Expected functions" {
        It "Exports the expected function <_>" -ForEach $expectedFunctions {
            $_ | Should -BeIn $exportedFunctions -Because "We expect the AgileBattery module to export the function $_"
        }
    }

    Context "Good Practices on Script <_>" -ForEach $scripts {

        BeforeAll {
            $scriptpath = $PsItem.FullName

        }
        BeforeDiscovery {
            $scriptpath = $PsItem.FullName
        }

        It 'The Script Analyzer Rule <_.RuleName> Should not fail' -ForEach $Tests {
            $rulefailures = Invoke-ScriptAnalyzer -Path $scriptpath -IncludeRule $PsItem.RuleName -Settings $PsItem.PsScriptAnalyzerSettings
            $message = ($rulefailures | Select-Object Message -Unique).Message
            $lines = $rulefailures.Line -join ','
            $Because = 'Script Analyzer says the rules have been broken on lines {3} with Message {0} Check in VSCode Problems tab or Run Invoke-ScriptAnalyzer -Script {1} -Settings {2}' -f $message, $scriptpath, $PsScriptAnalyzerSettings, $lines
            $rulefailures.Count | Should -Be 0 -Because $Because
        }
    }
}

Describe 'Testing help for <_>' -Tag Help -ForEach $expectedFunctions {

    BeforeAll {
        $Help = Get-Help $PsItem -ErrorAction SilentlyContinue
    }

    Context 'General help' {
        It 'Synopsis should not be auto-generated or empty' {
            $Because = 'We are good citizens and write good help'
            $Help.Synopsis | Should -Not -BeLike 'Short description*' -Because $Because
            $Help.Synopsis[0] | Should -Not -Match '\n' -Because $Because
        }
        It 'Description should not be auto-generated or empty' {
            $Because = 'We are good citizens and write good help'
            $Help.Description | Should -Not -BeLike '*Long description*' -Because $Because
            $Help.Description | Should -Not -BeNullOrEmpty -Because $Because
        }
    }

    Context 'Examples help' {
        It 'There should be more than one example' {
            $Because = 'Most commands should have more than one example to explain and we are good citizens and write good help'
            $Help.Examples.example.Count | Should -BeGreaterThan 1 -Because $Because
        }

        It 'There should be code for <_.title>' -ForEach $Help.Examples.Example {
            $Because = 'All examples should have code otherwise what is the point? and we are good citizens and write good help'
            $PsItem.Code | Should -Not -BeNullOrEmpty -Because $Because
            $PsItem.Code | Should -Not -BeLike '*An example*' -Because $Because
        }
        It 'There should be remarks for <_.title>' -ForEach $Help.Examples.Example {
            $Because = 'All examples should have explanations otherwise what is the point? and we are good citizens and write good help'
            $PsItem.remarks[0] | Should -Not -Be '@{Text=}' -Because $Because
        }
    }

    Context 'Parameters help' {
        It 'Parameter <_.name> should have help' -ForEach ($command.ParameterSets.Parameters | Where-Object Name -NotIn 'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable', 'OutBuffer', 'OutVariable', 'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable', 'Confirm', 'WhatIf') {
            $Because = 'Every parameter should have help and we are good citizens and write good help'
            $_.Description.Text | Should -Not -BeNullOrEmpty -Because $Because
            $_.Description.Text | Should -Not -Be 'Parameter description' -Because $Because
        }
    }
}