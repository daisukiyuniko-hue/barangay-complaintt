# Barangay Complaint & Concern Reporting System

An online complaint and concern reporting system for a barangay. Residents create a
free account, report a concern (pothole, broken streetlight, waste buildup, noise,
and more), and follow the status from **Pending** to **Resolved**. Administrators
manage every report and every resident account.

Built with Windows PowerShell 5.1 and plain HTML/CSS/JavaScript — **no installation
required**. Double-click `start.bat` and the system runs.

---

## Quick start

```
1. Double-click  start.bat
2. Your browser opens automatically at  http://localhost:8080/
```

> ### Keep the black window open
> The server runs inside that console window. **If you close it, the address
> stops working** and the browser will say the page can't be reached. Start it
> again with `start.bat` when you want to use the system.
> To stop it deliberately, press **Ctrl + C** in that window.

Double-clicking `start.bat` when the server is already running is safe — it just
opens the browser instead of starting a second copy.

Your data is saved to `data\db.json` and is still there the next time you start it.

### Demo accounts

| Role | Email | Password |
| --- | --- | --- |
| Administrator | `admin@barangay.gov.ph` | `Admin@12345` |
| Resident | `resident@barangay.gov.ph` | `Resident@12345` |

These are created automatically the first time the system starts. You can register
your own account from the landing page at any time.

### Command line options

```powershell
.\start.bat                      # default port 8080
.\start.bat -Port 8090          # use a different port
.\start.bat -Reset               # wipe the database and start fresh
.\server.ps1 -NoBrowser          # do not open a browser automatically
```

### If the page can't be reached

| Symptom | Cause | Fix |
| --- | --- | --- |
| Browser says the page can't be reached | The console window was closed | Double-click `start.bat` |
| "The web server could not start ... conflicts with an existing registration" | Another program already owns port 8080 | Close it, or use `.\start.bat -Port 8090` |
| A `.bat` window closes instantly | PowerShell blocked | Right-click `start.bat` → Run as administrator |

Check whether the server is alive at any time: <http://localhost:8080/health>
returns a small JSON status payload.

---

## What the system does

### 1. Landing page (public — no login needed)

`http://localhost:8080/`

* Business name — *Barangay San Isidro Complaint & Concern Reporting System*
* Short description of what the system does
* **Services section** listing all 8 categories of concern that can be reported,
  each with its own icon image
* **Images** — a hero illustration of the Barangay Hall and a community illustration
* **Clear calls to action** — *Create a free account*, *Sign in*, *Report a concern*,
  *Start reporting now*
* How it works (4 steps), why report online, office and emergency contacts, FAQ
* Fully **responsive** — mobile-first CSS with 13 breakpoints, a hamburger menu, and
  data tables that collapse into readable cards on a phone

### 2. Accounts (two levels of access)

| | Resident | Administrator |
| --- | --- | --- |
| Register / log in / log out | yes | yes |
| File a complaint | yes | yes |
| View complaints | **own only** | **all residents'** |
| Edit / delete a complaint | own, while still *Pending* | any |
| Change report status and add notes | no | yes |
| Manage resident accounts | no | yes |
| Promote / deactivate / delete accounts | no | yes |

**Register** with name, email, password (plus optional phone and address).
Passwords must be at least 8 characters and contain a letter, a number and a
special character.

**Passwords are hashed.** They are never stored, logged or transmitted in plain
text — see *Security* below.

**Protected pages.** `/dashboard`, `/complaints`, `/complaints/new`, `/profile`,
`/profile/password` and `/users` all check for a valid session first. An anonymous
visitor is redirected to `/login?next=...` and returned to the page they wanted after
signing in. Admin-only pages return `403` to a signed-in resident.

### 3. CRUD

**Core entity: Complaints.** Every report has a reference number (`BCR-2026-0001`),
a title, category, priority, location, description, status and timestamps.

| Action | How |
| --- | --- |
| **Create** | `/complaints/new` — validated form, auto-assigned reference number |
| **Read** | list with search + category/status/priority filters + pagination, and a detail page with a progress timeline |
| **Update** | edit the details while *Pending*; administrators can edit any time and change the status with a note to the resident |
| **Delete** | a dedicated confirmation page shows the record and warns that it cannot be undone. The server requires an explicit `confirm=yes` plus a valid CSRF token. |

**User accounts** also get full Create / Read / Update / Delete in the admin area
(`/users`, `/users/new`).

**Validation** — required fields, length limits, email and phone formats, a password
policy, and whitelisted category/priority values. Every problem is reported at once
in plain language, next to the field, and the form keeps what you already typed.

**Delete confirmation** is enforced on both complaints and accounts.

---

## Project structure

```
Default Project/
├── start.bat                      double-click launcher
├── server.ps1                     entry point: loads modules, starts the server
├── test-app.ps1                   184-check end-to-end test suite
├── test-render.ps1                renders every page and checks the markup
├── README.md
│
├── app/                           --- backend (PowerShell) ---
│   ├── Core.ps1                   settings, helpers, HTTP request routing, responses
│   ├── Database.ps1               file-backed JSON store, queries, seed data
│   ├── Security.ps1               password hashing, sessions, CSRF, access guards
│   ├── Validation.ps1             all input validation rules
│   ├── Views.ps1                  page layout and reusable UI components
│   └── Controllers/
│       ├── PublicController.ps1       landing page + dashboard
│       ├── AuthController.ps1         register, login, logout, profile
│       ├── ComplaintController.ps1    complaint CRUD
│       ├── UserController.ps1         admin account management
│       └── StaticController.ps1       css / js / images / health probe
│
├── public/                        --- frontend (static assets) ---
│   ├── css/style.css              responsive stylesheet
│   ├── js/app.js                  nav, password strength, counters, confirms
│   └── img/                       logo, hero illustration, 8 service icons
│
└── data/
    └── db.json                    the database — created on first run
```

---

## Database

`data\db.json` is the database. It holds `users`, `complaints`, `sessions` and an
`activityLog`. It is written atomically (write to a temp file, then rename) so an
interrupted save can never corrupt it, and a backup is made if the file is ever
unreadable. Everything survives a restart.

---

## Security

| Concern | How it is handled |
| --- | --- |
| **Password storage** | PBKDF2-HMAC-SHA1, **120,000 iterations**, a random 16-byte salt per account, 32-byte hash, compared in constant time. Only `passwordSalt` / `passwordHash` are stored — there is no `password` field anywhere. |
| **Sessions** | 32-byte random tokens stored server-side. The cookie is `HttpOnly`, `SameSite=Lax`, `Path=/`, and expires after 8 hours. The token is regenerated on sign-in (prevents session fixation) and on password change. |
| **CSRF** | Every state-changing form carries a token. Signed-in users get a per-session token; signed-out users get a double-submit cookie token. Invalid tokens are rejected with `400`. |
| **XSS** | All dynamic output is HTML-encoded through `HtmlEncode()`. |
| **SQL injection** | Not applicable — there is no SQL layer. All queries are PowerShell filters over in-memory objects. |
| **Path traversal** | Static file requests are resolved and verified to stay inside `public\`. |
| **Privilege escalation** | Role checks happen on the server for every admin route; the UI hides links as a convenience only. A resident calling an admin endpoint directly gets `403`. |
| **Access control** | A resident can only open, edit or delete their own reports. Ownership is verified server-side on every request, not just hidden in the interface. |
| **Open redirect** | The `?next=` parameter only accepts same-site relative paths. |
| **Account safety** | Admins cannot delete or demote themselves, and cannot remove the last active administrator. Deactivating an account kills its live sessions immediately. |

---

## Testing

Start the server first, then run either suite in a second console:

```powershell
# 184 end-to-end checks
.\start.bat -Port 8123
powershell -ExecutionPolicy Bypass -File .\test-app.ps1 -Port 8123
```

```
  ALL TESTS PASSED   (184 checks)
```

`test-app.ps1` covers the landing page requirements, page protection, registration,
login, logout, validation, the full complaint CRUD cycle, delete confirmation, data
persistence, both access levels, and security (CSRF, XSS, path traversal,
privilege escalation, cookie hardening).

```powershell
# renders every page as each role and checks the markup
powershell -ExecutionPolicy Bypass -File .\test-render.ps1 -Port 8123
```

```
  RENDER CHECK: all pages clean
```

`test-render.ps1` verifies that no template artefacts leak into the HTML, that tags
are balanced, and that every page has a doctype, charset, viewport tag, stylesheet
and alt text on its images.

---

## Configuration

Open `app\Core.ps1` and edit the `$global:Config` block to change the barangay name,
contact details, session length, PBKDF2 iteration count, port or page size. The
categories, priorities and statuses are in the same file.

```powershell
$global:Config = @{
    BarangayName     = 'Barangay San Isidro'
    Municipality     = 'City of Antipolo'
    Port             = 8080
    SessionHours     = 8
    Pbkdf2Iterations = 120000
    PageSize         = 8
    ...
}
```

### API endpoint

`GET /health` returns a small JSON status payload — useful to confirm the server and
the database are alive.

---

## Requirements

* Windows 10 / 11
* Windows PowerShell 5.1 or later (already included with Windows)
* A modern browser (Chrome, Edge, Firefox)

No internet connection is needed — the images are SVG files in `public\img`, there
are no external fonts, CDNs or third-party scripts.
