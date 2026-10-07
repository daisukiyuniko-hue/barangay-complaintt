# ============================================================================
#  Controllers/StaticController.ps1 - images, CSS, JS and the health probe
# ============================================================================

function Invoke-StaticAsset {
    param($Ctx, [string]$RelativePath = '')

    $prefixes = @{
        '/img/' = 'img'
        '/css/' = 'css'
        '/js/'  = 'js'
    }

    $sub = ''
    if ($RelativePath -ne '') {
        $sub = $RelativePath
    }
    else {
        foreach ($prefix in $prefixes.Keys) {
            if ($Ctx.Path.StartsWith($prefix)) {
                $sub = $prefixes[$prefix] + '/' + $Ctx.Path.Substring($prefix.Length)
                break
            }
        }
    }

    if ($sub -eq '') {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 404 -Heading 'Asset not found' `
            -Message 'The requested file does not exist.'
        return
    }

    Send-StaticAsset -Response $Ctx.Response -RootPath $global:PublicDir -RelativePath $sub
}

function Invoke-HealthCheck {
    param($Ctx)

    $payload = [pscustomobject]@{
        status       = 'ok'
        application  = $global:Config.SiteName
        barangay     = $global:Config.BarangayName
        serverTime   = (Get-NowIso)
        databaseFile = (Split-Path -Leaf $global:DbPath)
        users        = @(Get-AllUsers).Count
        complaints   = @(Get-AllComplaints).Count
        activeSessions = @(Get-AllSessions).Count
    }
    Send-Json -Response $Ctx.Response -Data $payload
}
