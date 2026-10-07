# ============================================================================
#  Database.ps1 - File-backed JSON store (users, complaints, sessions)
#  Data is written atomically to data\db.json and survives restarts.
# ============================================================================

$global:DataDir = $null
$global:DbPath  = $null
$global:Db      = $null

function New-EmptyDb {
    return [pscustomobject]@{
        meta = [pscustomobject]@{
            schemaVersion = 1
            createdAt      = (Get-NowIso)
        }
        users        = @()
        complaints   = @()
        sessions     = @()
        activityLog  = @()
        counters     = [pscustomobject]@{ complaint = 0 }
    }
}

function Initialize-Database {
    param([switch]$Reset)

    $global:DataDir = Join-Path $global:AppRoot 'data'
    if (-not (Test-Path -LiteralPath $global:DataDir)) {
        New-Item -ItemType Directory -Path $global:DataDir -Force | Out-Null
    }
    $global:DbPath = Join-Path $global:DataDir 'db.json'

    if ($Reset -and (Test-Path -LiteralPath $global:DbPath)) {
        Remove-Item -LiteralPath $global:DbPath -Force
        Write-Host '  [db] existing database removed (--reset)' -ForegroundColor Yellow
    }

    if (Test-Path -LiteralPath $global:DbPath) {
        try {
            $raw = Get-Content -LiteralPath $global:DbPath -Raw -Encoding UTF8
            if ([string]::IsNullOrWhiteSpace($raw)) { throw 'empty file' }
            $global:Db = $raw | ConvertFrom-Json
            Write-Host '  [db] loaded existing database' -ForegroundColor DarkGray
        }
        catch {
            $backup = "$($global:DbPath).corrupt-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -LiteralPath $global:DbPath -Destination $backup -Force
            Write-Host "  [db] database was unreadable. Backed up to $backup" -ForegroundColor Yellow
            $global:Db = New-EmptyDb
            Save-Database
        }
    }
    else {
        $global:Db = New-EmptyDb
        Write-Host '  [db] created new database file' -ForegroundColor DarkGray
    }

    Repair-DbShape
    $null = Remove-ExpiredSessions
    Seed-InitialData
    Save-Database
}

# Makes sure every collection exists and is a real array even if the file was
# hand-edited, so later code can rely on .Count / foreach.
function Repair-DbShape {
    foreach ($name in @('users', 'complaints', 'sessions', 'activityLog')) {
        $value = $global:Db.$name
        if ($null -eq $value) {
            $global:Db | Add-Member -NotePropertyName $name -NotePropertyValue @() -Force
        }
        elseif ($value -isnot [array]) {
            $global:Db.$name = @($value)
        }
    }
    if ($null -eq $global:Db.counters) {
        $global:Db | Add-Member -NotePropertyName 'counters' `
            -NotePropertyValue ([pscustomobject]@{ complaint = 0 }) -Force
    }
    if ($null -eq $global:Db.counters.complaint) {
        $global:Db.counters.complaint = 0
    }
    if ($null -eq $global:Db.meta) {
        $global:Db | Add-Member -NotePropertyName 'meta' `
            -NotePropertyValue ([pscustomobject]@{ schemaVersion = 1; createdAt = (Get-NowIso) }) -Force
    }
}

function Save-Database {
    $json = $global:Db | ConvertTo-Json -Depth 12
    $tmp  = "$($global:DbPath).tmp"
    # Write-then-move so an interrupted write can never corrupt db.json.
    Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8 -NoNewline
    Move-Item -LiteralPath $tmp -Destination $global:DbPath -Force
}

# ------------------------------------------------------------------ queries --
function Get-AllUsers { return @($global:Db.users) }

function Get-UserById {
    param([string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $null }
    return (@($global:Db.users) | Where-Object { $_.id -eq $Id } | Select-Object -First 1)
}

function Get-UserByEmail {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return $null }
    $needle = $Email.Trim().ToLowerInvariant()
    return (@($global:Db.users) | Where-Object { ([string]$_.email).ToLowerInvariant() -eq $needle } | Select-Object -First 1)
}

function Save-User {
    param($User)
    $users = @(Get-AllUsers)
    $index = -1
    for ($i = 0; $i -lt $users.Count; $i++) { if ($users[$i].id -eq $User.id) { $index = $i; break } }
    if ($index -ge 0) { $users[$index] = $User } else { $users += $User }
    $global:Db.users = @($users)
    Save-Database
    return $User
}

function Remove-UserRecord {
    param([string]$Id)
    $global:Db.users = @(@($global:Db.users) | Where-Object { $_.id -ne $Id })
    Save-Database
}

function Get-AllComplaints { return @($global:Db.complaints) }

function Get-ComplaintById {
    param([string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $null }
    return (@($global:Db.complaints) | Where-Object { $_.id -eq $Id } | Select-Object -First 1)
}

function Save-Complaint {
    param($Complaint)
    $items = @(Get-AllComplaints)
    $index = -1
    for ($i = 0; $i -lt $items.Count; $i++) { if ($items[$i].id -eq $Complaint.id) { $index = $i; break } }
    if ($index -ge 0) { $items[$index] = $Complaint } else { $items += $Complaint }
    $global:Db.complaints = @($items)
    Save-Database
    return $Complaint
}

function Remove-ComplaintRecord {
    param([string]$Id)
    $global:Db.complaints = @(@($global:Db.complaints) | Where-Object { $_.id -ne $Id })
    Save-Database
}

function New-ComplaintReference {
    $year  = (Get-Date).Year
    $seq   = [int]$global:Db.counters.complaint + 1
    $global:Db.counters.complaint = $seq
    return ('BCR-{0}-{1:D4}' -f $year, $seq)
}

function Get-ComplaintStats {
    param([string]$UserId)

    $all = if ([string]::IsNullOrWhiteSpace($UserId)) { @(Get-AllComplaints) }
           else { @(Get-AllComplaints | Where-Object { $_.reporterId -eq $UserId }) }

    $stats = [pscustomobject]@{
        Total    = $all.Count
        Pending  = @($all | Where-Object { $_.status -eq 'Pending' }).Count
        InReview = @($all | Where-Object { $_.status -eq 'In Review' }).Count
        Resolved = @($all | Where-Object { $_.status -eq 'Resolved' }).Count
        Rejected = @($all | Where-Object { $_.status -eq 'Rejected' }).Count
        Urgent   = @($all | Where-Object { $_.priority -eq 'Urgent' -and $_.status -ne 'Resolved' }).Count
    }
    return $stats
}

function Add-ActivityLog {
    param([string]$Action, [string]$ActorId, [string]$Detail)
    $entry = [pscustomobject]@{
        id        = (New-Id 'log')
        action    = $Action
        actorId   = $ActorId
        detail    = $Detail
        createdAt = (Get-NowIso)
    }
    $log = @($global:Db.activityLog)
    $log += $entry
    if ($log.Count -gt 200) { $log = @($log[-200..-1]) }
    $global:Db.activityLog = @($log)
}

# --------------------------------------------------------------- seed data ---
function Seed-InitialData {
    $admin = Get-UserByEmail 'admin@barangay.gov.ph'
    if ($null -eq $admin) {
        $admin = New-UserRecord -Name 'Barangay Administrator' `
            -Email 'admin@barangay.gov.ph' -Password 'Admin@12345' `
            -Role 'admin' -Phone '0917 000 0000' -Address 'Barangay Hall, Purok 3'
        Write-Host '  [db] seeded admin account' -ForegroundColor DarkGray
    }

    $resident = Get-UserByEmail 'resident@barangay.gov.ph'
    if ($null -eq $resident) {
        $resident = New-UserRecord -Name 'Juan Dela Cruz' `
            -Email 'resident@barangay.gov.ph' -Password 'Resident@12345' `
            -Role 'resident' -Phone '0918 123 4567' -Address 'Purok 5, San Isidro'
        Write-Host '  [db] seeded resident account' -ForegroundColor DarkGray
    }

    if (@(Get-AllComplaints).Count -eq 0) {
        Seed-SampleComplaints -Reporter $resident
        Write-Host '  [db] seeded sample complaints' -ForegroundColor DarkGray
    }
}

function Seed-SampleComplaints {
    param($Reporter)

    $samples = @(
        @{ title = 'Deep pothole in front of Barangay Hall'; category = 'Road & Infrastructure'; priority = 'Urgent';
           location = 'Main Road, front of Barangay Hall';
           description = 'There is a very deep pothole right in front of the Barangay Hall entrance. Several motorcycles have already fallen into it and it is very dangerous at night because there is no lighting there.';
           status = 'In Review'; notes = 'Road crew scheduled to patch this week. Temporary warning signs installed.'; hoursAgo = 30 }
        @{ title = 'Streetlight not working since last week'; category = 'Electricity & Utilities'; priority = 'Medium';
           location = 'Purok 5 corner';
           description = 'The streetlight at the corner of Purok 5 has not been working for about a week. At night the area becomes very dark and unsafe for pedestrians, especially for children going to school.';
           status = 'Pending'; notes = ''; hoursAgo = 52 }
        @{ title = 'Garbage pile up near the creek'; category = 'Water & Sanitation'; priority = 'High';
           location = 'Purok 2, near the creek';
           description = 'Garbage has been piling up near the creek for more than two weeks. It smells bad and flies are everywhere. When it rains the waste flows into the creek and affects the households downstream.';
           status = 'Resolved'; notes = 'Waste collection schedule moved to twice a week. Area cleared on site.'; hoursAgo = 96 }
        @{ title = 'Loud videoke every weekend past midnight'; category = 'Noise & Nuisance'; priority = 'Medium';
           location = 'Purok 7';
           description = 'Our neighbour plays loud videoke music every weekend until past midnight. We cannot sleep and our small children are already exhausted by school time.';
           status = 'In Review'; notes = 'Barangay Peace and Order officer scheduled to mediate.'; hoursAgo = 140 }
        @{ title = 'Water supply interruption every afternoon'; category = 'Water & Sanitation'; priority = 'High';
           location = 'Purok 4';
           description = 'Our water supply is cut off almost every afternoon from 1 PM to about 5 PM. This has been happening for three weeks already and it is very inconvenient for the households in our purok.';
           status = 'Pending'; notes = ''; hoursAgo = 190 }
        @{ title = 'Broken railing on the basketball court'; category = 'Health & Safety'; priority = 'Urgent';
           location = 'Barangay Sports Complex';
           description = 'One side of the basketball court railing is broken and hanging. Children play there every day and the sharp metal could badly hurt somebody if they run into it.';
           status = 'Resolved'; notes = 'Railing replaced with a new steel one. Court reopened.'; hoursAgo = 260 }
    )

    $adminId = (Get-UserByEmail 'admin@barangay.gov.ph').id

    foreach ($s in $samples) {
        $created = (Get-Date).ToUniversalTime().AddHours(-1 * $s.hoursAgo)
        $touchedBy = ''
        if ($s.status -ne 'Pending') { $touchedBy = $adminId }
        $record = [pscustomobject]@{
            id            = (New-Id 'cmp')
            referenceNo   = (New-ComplaintReference)
            title         = $s.title
            description   = $s.description
            category      = $s.category
            priority      = $s.priority
            status        = $s.status
            location      = $s.location
            reporterId    = $Reporter.id
            reporterName  = $Reporter.name
            reporterEmail = $Reporter.email
            reporterPhone = $Reporter.phone
            adminNotes    = $s.notes
            createdAt     = $created.ToString('o')
            updatedAt     = $created.AddMinutes(30).ToString('o')
            updatedBy     = $touchedBy
        }
        $null = Save-Complaint $record
    }
}
