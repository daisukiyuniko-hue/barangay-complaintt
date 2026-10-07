# Renders every page (signed out, resident, admin) and scans for template
# artefacts, unbalanced tags and unencoded output.
param([int]$Port = 8123)
$Base = "http://localhost:$Port"

function New-Client { $j = New-Object System.Net.CookieContainer; [pscustomobject]@{ Base = ([uri]$Base); Jar = $j } }

function Get-Page {
    param($Client, [string]$Path)
    $r = [System.Net.HttpWebRequest]::Create($Path)
    $r.Method = 'GET'; $r.AllowAutoRedirect = $true; $r.CookieContainer = $Client.Jar
    $r.UserAgent = 'render-check'
    try { $resp = $r.GetResponse() } catch [System.Net.WebException] { $resp = $_.Exception.Response }
    $rd = New-Object System.IO.StreamReader($resp.GetResponseStream()); $t = $rd.ReadToEnd(); $rd.Close()
    $code = [int]$resp.StatusCode; $resp.Close()
    return [pscustomobject]@{ Status = $code; Body = $t }
}

function Login {
    param([string]$Email, [string]$Password)
    $c = New-Client
    $p = Get-Page $c "$Base/login"
    $csrf = [regex]::Match($p.Body, 'name="csrf_token" value="([^"]+)"').Groups[1].Value
    $r = [System.Net.HttpWebRequest]::Create("$Base/login")
    $r.Method = 'POST'; $r.AllowAutoRedirect = $false; $r.CookieContainer = $c.Jar
    $r.ContentType = 'application/x-www-form-urlencoded'
    $body = 'csrf_token=' + [uri]::EscapeDataString($csrf) + '&email=' + [uri]::EscapeDataString($Email) + '&password=' + [uri]::EscapeDataString($Password)
    $d = [Text.Encoding]::UTF8.GetBytes($body); $r.ContentLength = $d.Length
    $s = $r.GetRequestStream(); $s.Write($d, 0, $d.Length); $s.Close()
    $resp = $r.GetResponse(); $resp.Close()
    return $c
}

$bad = 0
function Scan {
    param([string]$Label, [string]$Html)

    $issues = @()

    foreach ($artefact in @('__CSRF__', '@{', 'System.Object[]', 'System.Collections', '$null', '$(', '$Ctx', '$Body', 'PSCustomObject', 'Hashtable')) {
        if ($Html.Contains($artefact)) { $issues += "template artefact '$artefact' leaked" }
    }
    if ($Html -match '\$global:')            { $issues += 'leaked $global: reference' }
    if ($Html -match '<b>\s*</b>:')          { $issues += 'malformed emphasis tag' }
    if ($Html -match 'ArrayList')            { $issues += 'leaked ArrayList' }

    # tag balance for the structural elements we render
    foreach ($tag in @('div', 'section', 'form', 'table', 'article', 'main', 'nav', 'header', 'footer', 'aside')) {
        $open  = ([regex]::Matches($Html, "<$tag[\s>]")).Count
        $close = ([regex]::Matches($Html, "</$tag>")).Count
        if ($open -ne $close) { $issues += "unbalanced <$tag>: $open open vs $close closed" }
    }

    # every page must declare charset + viewport and load the stylesheet
    if ($Html -notmatch '<meta charset="utf-8">')      { $issues += 'missing charset meta' }
    if ($Html -notmatch 'name="viewport"')             { $issues += 'missing viewport meta' }
    if ($Html -notmatch '/css/style\.css')             { $issues += 'stylesheet not linked' }
    if ($Html -notmatch '<!DOCTYPE html>')            { $issues += 'missing doctype' }

    # accessibility basics
    if ($Html -match '<img(?![^>]*alt=)[^>]*>')        { $issues += 'an <img> is missing alt text' }
    if ($Html -match '<button(?![^>]*type=)[^>]*>')     { $issues += 'a <button> is missing type=' }

    if ($issues.Count -eq 0) {
        Write-Host ("  OK    " + $Label.PadRight(46) + " (" + $Html.Length + " bytes)") -ForegroundColor Green
    } else {
        $script:bad++
        Write-Host ("  ISSUE " + $Label) -ForegroundColor Red
        $issues | ForEach-Object { Write-Host ("          - " + $_) -ForegroundColor Red }
    }
}

$anon = New-Client
Write-Host ''
Write-Host '=== Anonymous (signed out) ===' -ForegroundColor Cyan
foreach ($p in @('/', '/login', '/register', '/nope-404')) {
    $r = Get-Page $anon "$Base$p"
    Scan "$p  [$($r.Status)]" $r.Body
}

Write-Host ''
Write-Host '=== Resident ===' -ForegroundColor Cyan
$resident = Login 'resident@barangay.gov.ph' 'Resident@12345'
foreach ($p in @('/dashboard', '/complaints', '/complaints/new', '/profile', '/profile/password', '/users')) {
    $r = Get-Page $resident "$Base$p"
    Scan "$p  [$($r.Status)]" $r.Body
}

$r = Get-Page $resident "$Base/complaints"
$id = [regex]::Match($r.Body, 'href="/complaints/(cmp_[A-Za-z0-9\-_]+)"').Groups[1].Value
foreach ($p in @("/complaints/$id", "/complaints/$id/edit", "/complaints/$id/delete")) {
    $r = Get-Page $resident "$Base$p"
    Scan "$p  [$($r.Status)]" $r.Body
}

Write-Host ''
Write-Host '=== Administrator ===' -ForegroundColor Cyan
$admin = Login 'admin@barangay.gov.ph' 'Admin@12345'
foreach ($p in @('/dashboard', '/complaints', '/users', '/users/new')) {
    $r = Get-Page $admin "$Base$p"
    Scan "$p  [$($r.Status)]" $r.Body
}
$r = Get-Page $admin "$Base/complaints"
$id = [regex]::Match($r.Body, 'href="/complaints/(cmp_[A-Za-z0-9\-_]+)"').Groups[1].Value
$r = Get-Page $admin "$Base/complaints/$id"
Scan "/complaints/$id  [$($r.Status)]" $r.Body

Write-Host ''
Write-Host '=== Empty-result states ===' -ForegroundColor Cyan
$r = Get-Page $resident "$Base/complaints?q=zzzznothingmatcheszzzz"
Scan "/complaints (no results)  [$($r.Status)]" $r.Body
$r = Get-Page $admin "$Base/users?q=zzzznothingmatcheszzzz"
Scan "/users (no results)  [$($r.Status)]" $r.Body

Write-Host ''
if ($bad -eq 0) { Write-Host '  RENDER CHECK: all pages clean' -ForegroundColor Green }
else { Write-Host ("  RENDER CHECK: $bad page(s) with issues") -ForegroundColor Red; exit 1 }
