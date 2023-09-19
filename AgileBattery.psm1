$teslaBaseURI = "https://owner-api.teslamotors.com/"
$teslaAuthURI = "https://auth.tesla.com/oauth2/v3/token"
     
function Get-TeslaApiToken{
    <#
        .SYNOPSIS 
        Retreives a Tesla API token when provided with a valid refresh token

        .PARAMETER RefreshToken
        A valid Tesla refresh token which you can generate from https://tesla-info.com/tesla-token.php
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RefreshToken
    )

    try {
  
        $params = @{
            "grant_type" ="refresh_token"
            "client_id"= "ownerapi"
            "refresh_token"= "$refreshToken"
            "scope"= "openid email offline_access"
        }
  
        $resp = Invoke-RestMethod -Method POST -Uri $teslaAuthURI -Body $params

        $resp.access_token

    }catch{
        throw "Could not retrieve a valid refresh token: $_"
    }

}

function Get-OctopusAgilePricing{
    <#
    .SYNOPSIS 
    Retrieves the Octopus Agile pricing tariff data

    .DESCRIPTION
    Retrieves a structured json file with the current days agile pricing rates per each half hour interval for your DNO region. 

    .PARAMETER DistributionNetworkOperator
    Character that represents the DNO of your area. 
    A â Eastern England
    B â East Midlands
    C â London
    D â Merseyside and Northern Wales
    E â West Midlands
    F â North Eastern England
    G â North Western England
    H â Southern England
    J â South Eastern England
    K â Southern Wales
    L â South Western England
    M â Yorkshire
    N â Southern Scotland
    P â Northern Scotland           

    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [ValidateSet("A","B","C","D","E","F","G","H","J","K","L","M","N","P")]
        [char]$DistributionNetworkOperator
    )

      
    try {
        $octopusAgileURI = "https://api.octopus.energy/v1/products/AGILE-FLEX-22-11-25/electricity-tariffs/E-1R-AGILE-FLEX-22-11-25-$DistributionNetworkOperator/standard-unit-rates/"
        $resp = invoke-webrequest $octopusAgileURI
        $json = $resp.Content | convertfrom-json
        $json.results
    }
    catch {
        throw "Could not retrieve and parse Octopus Agile pricing: $_"
    }
  
}

function Get-TeslaProducts{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [string]$ApiToken
    )

   (Invoke-RestMethod -Method Get -Headers @{ "Authorization"="Bearer $ApiToken" } -Uri "$teslaBaseURI/api/1/products").response
  
}

function Get-TeslaEnergySiteId{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [string]$ApiToken
    )

    (Get-TeslaProducts $ApiToken).energy_site_id
    
}

function Get-TeslaPowerWallId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [string]$ApiToken
    )

    $response = Get-TeslaProducts $ApiToken
    $battery = $response | Where-Object {$_.resource_type -eq "battery"} | Select-Object -first 1
    $battery.id 
}

function Get-TeslaPowerWallStatus{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [string]$ApiToken
    )
    Invoke-RestMethod -method Get -URI "$teslaBaseURI/api/1/energy_sites/$energy_site_id/site_info"  -Headers @{ "Authorization"="Bearer $ApiToken" }

}

# function to control the powerwall 
function Set-TeslaEnergySiteReservePower{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [string]$ApiToken,
        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [string]$EnergySiteId,
        [Parameter(Mandatory,Position=1)]
        [int]$ReservePowerPercentage
    )

    Invoke-RestMethod -Method Post -Headers @{ "Authorization"="Bearer $ApiToken" } -body ( @{"backup_reserve_percent"=$ReservePowerPercentage}|convertto-json) -Uri "$teslaBaseURI/api/1/energy_sites/$EnergySiteId/backup" -ContentType 'application/json'

}


#main loop
function Invoke-AgileBatteryControl{
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RefreshToken,

        [Parameter()]
        [char]$DNORegion = "J"
    )

    if(!$RefreshToken){
        #try loading from token.txt
    }

    #try getting an API token now, else bomb out

    #try getting other static essentials, else bomb out

    $prices = "ff"


    # have everything we need now, so we can do the main loop
    $loop = $true
    $powerwallId = $null
    
    while($loop){
        try {
            # get prices 
            $currentPrices = Get-OctopusAgilePricing $DNORegion

            # refresh API token
            $apiToken = Get-TeslaApiToken $RefreshToken

                
                $powerwallId = Get-TeslaPowerWallId -ApiToken $apiToken

                if(!$powerwallId){
                    $loop = $false
                    throw "Could not retrieve powerwall information, aborting"
                }

            

        }
        catch {
            Clear-Host
            Write-Host "Encountered an error on this run, but will retry in 30s: $_"
            
        }
        Start-Sleep -Seconds 30
    }
}
