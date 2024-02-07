$teslaBaseURI = "https://owner-api.teslamotors.com/"
$teslaAuthURI = "https://auth.tesla.com/oauth2/v3/token"
     
function Get-TeslaApiToken {
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
            "grant_type"    = "refresh_token"
            "client_id"     = "ownerapi"
            "refresh_token" = "$refreshToken"
            "scope"         = "openid email offline_access"
        }
  
        $resp = Invoke-RestMethod -Method POST -Uri $teslaAuthURI -Body $params

        $resp.access_token

    }
    catch {
        throw "Could not retrieve a valid refresh token: $_"
    }

}

function Get-OctopusAgilePricing {
    <#
    .SYNOPSIS 
    Retrieves the Octopus Agile pricing tariff data

    .DESCRIPTION
    Retrieves a structured json file with the current days agile pricing rates per each half hour interval for your DNO region. 

    .PARAMETER DistributionNetworkOperator
    Character that represents the DNO of your area. 
    A - Eastern England
    B - East Midlands
    C - London
    D - Merseyside and Northern Wales
    E - West Midlands
    F - North Eastern England
    G - North Western England
    H - Southern England
    J - South Eastern England
    K - Southern Wales
    L - South Western England
    M - Yorkshire
    N - Southern Scotland
    P - Northern Scotland           

    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet("A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "P")]
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

function Get-TeslaProducts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$ApiToken
    )

   (Invoke-RestMethod -Method Get -Headers @{ "Authorization" = "Bearer $ApiToken" } -Uri "$teslaBaseURI/api/1/products").response
  
}

function Get-TeslaEnergySiteId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$ApiToken
    )

    (Get-TeslaProducts $ApiToken).energy_site_id
    
}

function Get-TeslaPowerWallId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$ApiToken
    )

    $response = Get-TeslaProducts $ApiToken
    $battery = $response | Where-Object { $_.resource_type -eq "battery" } | Select-Object -first 1
    $battery.id 
}

function Get-TeslaPowerWallStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$ApiToken
    )
    Invoke-RestMethod -method Get -URI "$teslaBaseURI/api/1/energy_sites/$energy_site_id/site_info"  -Headers @{ "Authorization" = "Bearer $ApiToken" }

}

# function to control the powerwall 
function Set-TeslaEnergySiteReservePower {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$ApiToken,
        [Parameter(Mandatory, ValueFromPipeline, Position = 1)]
        [string]$EnergySiteId,
        [Parameter(Mandatory, Position = 2)]
        [int]$ReservePowerPercentage
    )
    
    Invoke-RestMethod -Method Post -Headers @{ "Authorization" = "Bearer $ApiToken" } -body ( @{"backup_reserve_percent" = $ReservePowerPercentage } | convertto-json) -Uri "$teslaBaseURI/api/1/energy_sites/$EnergySiteId/backup" -ContentType 'application/json' | out-null

}


#main loop
function Invoke-AgileBatteryControl {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RefreshToken,

        [Parameter()]
        [string]$RefreshTokenPath = "token.txt",

        [Parameter()]
        [char]$DNORegion = "J",

        [Parameter()]
        [int]$HoursToChargePowerWall = 5,

        [Parameter()]
        [Boolean]$Loop = $true
    )

    if (-not $RefreshToken) {
        #try loading from token.txt if none specified on command line
        try {
            $RefreshToken = Get-Content $RefreshTokenPath -ErrorAction Stop
        }
        catch {
            throw "Could not load token from $RefreshTokenPath and no `$refreshToken was specified on the command line, aborting"
        }
    }

    # get API token
    $apiToken = Get-TeslaApiToken $RefreshToken
    
    # get Site Id                
    $energySiteId = [string](Get-TeslaEnergySiteId -ApiToken $apiToken)
            
    if (!$energySiteId) {
        $loop = $false
        throw "Could not retrieve energy site information, aborting"
    }

    
    do {
        try {

            # refresh API token
            $apiToken = Get-TeslaApiToken $RefreshToken

            # get the time 
            $now = [DateTime]::UtcNow 

            # get prices 
            $currentPrices = Get-OctopusAgilePricing $DNORegion
            $todaysPrices = $currentPrices | Where-Object { ([DateTime]$_.valid_from).ToUniversalTime().Date -eq $now.Date.ToUniversalTime() } 
            $cheapestHalfHourZones = $todaysPrices  | Sort-Object value_inc_vat | Select-Object -first ($HoursToChargePowerWall * 2)
            $cheapestPriceStartingZone = $cheapestHalfHourZones | Select-Object -ExpandProperty value_inc_vat -last 1 
            
            # work out if current time slot is in the cheap zone of the cheapest hours we want to charge the powerwall
            $currentTimeSlot = $todaysPrices | Where-Object { ($now -gt ([datetime]$_.valid_from).ToUniversalTime()) -and ($now -lt ([datetime]$_.valid_to).ToUniversalTime()) }
            $isCheapTimeSlot = $cheapestHalfHourZones | Where-Object { ($now -gt ([datetime]$_.valid_from).ToUniversalTime()) -and ($now -lt ([datetime]$_.valid_to).ToUniversalTime()) }
            $price = $currentTimeSlot.value_inc_vat
            
            if ($isCheapTimeSlot) {
                Write-Host "Cheapest time found :: $now :: $price :: Todays cheapest prices begin at $cheapestPriceStartingZone"

                # set powerwall to 100% reserve
                Set-TeslaEnergySiteReservePower -ApiToken $apiToken -EnergySiteId $energySiteId -ReservePowerPercentage 100
            }
            else {
                Write-host "Time Found but not in cheapest zone :: $now :: $price :: Todays cheapest prices begin at $cheapestPriceStartingZone"

                # set powerwall to 20% reserve
                Set-TeslaEnergySiteReservePower -ApiToken $apiToken -EnergySiteId $energySiteId -ReservePowerPercentage 20
            }
        }
        catch {
            Write-Host "Encountered an error on this run, but will retry in 30s: $_"            
        }
        Start-Sleep -Seconds 30
    }while ($loop)
}
