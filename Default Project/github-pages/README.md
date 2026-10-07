# Barangay Complaint & Concern Reporting System — Web Version

A **static** website (HTML + CSS + vanilla JavaScript). It deploys to
**GitHub Pages** with no build step, no server and no database setup.

Residents create a free account, report a concern (pothole, broken streetlight,
waste buildup, noise, and more), and follow the status from **Pending** to
**Resolved**. Administrators manage every report and every resident account.

---

## Deploy to GitHub Pages

### 1. Create the repository

On GitHub: **New repository** → name it (for example
`barangay-complaint-system`) → tick **Public** → **Create repository**.

### 2. Upload these files

In the repository, choose **Add file → Upload files** and drag in the contents of
the `github-pages` folder:

```
index.html
404.html
robots.txt
.nojekyll
assets/
├── css/styles.css
├── img/            (12 SVG files)
└── js/
    ├── crypto.js  store.js  auth.js  validate.js
    ├── ui.js  layout.js  router.js  app.js
    └── views/  (landing, auth, complaints, dashboard, users, data, errors)
```

> Keep the folder structure exactly as it is — the paths are referenced in
> `index.html`.

### 3. Turn on GitHub Pages

**Settings → Pages → Build and deployment**
* Source: **Deploy from a branch**
* Branch: **main** (or *master*), folder: **/ (root)**
* Save, wait ~30 seconds, reload the page

The site will be live at:

```
https://YOUR-USERNAME.github.io/barangay-complaint-system/
```

Every later push to `main` republishes automatically.

---

## Run it locally without deploying

The app uses `crypto.subtle`, which browsers only expose in a **secure context**.
`http://localhost` counts as secure, so opening the folder through any local web
server works and gives you the strong hashing path.

**Option A — VS Code** (already installed on this machine)

1. Open the `github-pages` folder in VS Code
2. Install the *Live Server* extension
3. Right-click `index.html` → **Open with Live Server**

**Option B — PowerShell one-liner**

```powershell
cd github-pages
python -m http.server 8080      # or: npx serve .
```

**Option C — just open the file**

Double-clicking `index.html` also works, but browsers treat `file://` as
insecure, so the app falls back to a built-in JavaScript hashing routine with
fewer rounds. The interface tells you when that happens.

---

## What it does

### Landing page (public, no login)
Business name, short description, an **8-category services menu**, **12 images**
(hero illustration, community illustration, one icon per category), clear calls to
action (*Create a free account*, *Sign in*, *Report a concern*), how-it-works,
office and emergency contacts, and an FAQ. Mobile-first and responsive.

### Accounts — two levels of access

| | Resident | Administrator |
| --- | --- | --- |
| Register / sign in / sign out | yes | yes |
| File a complaint | yes | yes |
| View complaints | **own only** | **everyone's** |
| Edit / delete a complaint | own, while still *Pending* | any |
| Change status, add notes | no | yes |
| Manage resident accounts | no | yes |
| Promote / deactivate / delete accounts | no | yes |

**Register** with name, email and password (phone and address optional). Password
rules: at least 8 characters with a letter, a number and a special character.

**Protected pages** — `#/dashboard`, `#/complaints`, `#/complaints/new`,
`#/profile`, `#/data` and `#/users` all check for a session first. An anonymous
visitor is redirected to the login page and returned to the page they wanted
after signing in. Admin pages return a 403 page to a signed-in resident.

### CRUD
**Create, Read, Update, Delete** on **Complaints** (reference numbers like
`BCR-2026-0001`), plus **Create, Read, Update, Delete** on **user accounts** in
the admin area.

* Validation with friendly messages beside each field, shown all at once, keeping
  what you typed
* Search plus category / status / priority filters, with pagination
* Editing is locked once a report leaves *Pending*, so the history stays accurate
* **Delete always asks first** — a confirmation page plus a modal, and the record
  is only removed when you confirm

---

## Where the data lives

Because GitHub Pages serves static files only, the "database" is your browser's
**localStorage**. This is stated plainly in the app (Data page and README) rather
than hidden.

What that means in practice:

* Data belongs to **one browser on one device**
* Clearing browsing data **deletes it**
* Nothing is uploaded, and nobody else can see it
* Two different browsers have two separate sets of records

### Moving data around
The **Data** page (`#/data`) lets you:

* **Export a backup** — downloads every account and report as JSON
* **Restore a backup** — replaces the current data with a file
* **Erase and reseed** — clears everything and restores the demo data

---

## Security

| Concern | How it is handled |
| --- | --- |
| **Password storage** | PBKDF2-HMAC-SHA256, **150,000 iterations**, a random 16-byte salt per account. Only the salt, the derived key and the iteration count are stored. There is no plain-text password field, and `Admin@12345` never appears in storage. |
| **Weak-hashing fallback** | `crypto.subtle` is unavailable outside a secure context, so a built-in JavaScript PBKDF2 is used with fewer rounds. The register page says so plainly instead of pretending. Serve over HTTPS or localhost for the strong version. |
| **Comparisons** | Password hashes are compared in constant time. |
| **XSS** | Every dynamic value passes through `esc()` before it reaches the page. A report titled `<script>alert(1)</script>` renders as text. |
| **Access control** | Ownership and role are checked in the store on every read and write, not just hidden in the interface. A resident calling an admin path directly gets a 403. |
| **Session** | Random 32-byte token in `sessionStorage` with an 8-hour expiry. Deactivating an account signs it out immediately. |
| **Open redirect** | The `?next=` parameter only accepts same-site relative paths. |
| **Destructive actions** | Confirmation is requested *before* the action runs, and cancelling really does cancel. |

---

## Demo accounts

Created automatically on first run.

| Role | Email | Password |
| --- | --- | --- |
| Administrator | `admin@barangay.gov.ph` | `Admin@12345` |
| Resident | `resident@barangay.gov.ph` | `Resident@12345` |

The **Fill demo credentials** button on the register page autofills the resident
account.

---

## Project structure

```
github-pages/
├── index.html            the only page - hash routing renders every view
├── 404.html              safety net for deep links
├── robots.txt
├── .nojekyll             stops GitHub Pages hiding files starting with _
└── assets/
    ├── css/styles.css    responsive stylesheet (23 media queries)
    ├── img/*.svg         logo, illustrations, 8 category icons
    └── js/
        ├── crypto.js     PBKDF2 hashing + pure-JS fallback
        ├── store.js      localStorage database, seed, export/import
        ├── auth.js       accounts, sessions, sign-in
        ├── validate.js   all input rules
        ├── ui.js         escaping, components, modal, toast
        ├── layout.js     header, navigation, footer, flash
        ├── router.js     hash routes and page guards
        ├── app.js        bootstrap and shared behaviour
        └── views/        one module per screen
```

Scripts are plain `<script>` tags rather than ES modules **on purpose**: ES modules
are blocked by browser CORS rules on `file://`, so plain scripts keep the
"double-click index.html" path working.

### Changing the details
Everything you'd want to edit lives at the top of `assets/js/layout.js`:

```js
var CONFIG = {
  barangay: 'Barangay San Isidro',
  municipality: 'City of Antipolo',
  description: '...',
  officeHours: '...',
  hotline: '+63 900 000 0000',
  email: '...',
  address: '...',
  pageSize: 8
};
```

Categories, priorities and statuses are in `assets/js/store.js`.

---

## Testing

Two suites are included for local use. They are **not** needed to deploy — delete
`__tests.js` and `__suite.js` before publishing if you prefer.

1. Start a local server (see above), open the site, then run in the browser
   console:

   ```javascript
   // unit checks: hashing, storage, roles, validation, CRUD, export/import, escaping
   await (await import('/__tests.js')).default;   // or: <script src="__tests.js"></script>
   await BCR_TEST.run();

   // end-to-end UI checks: guards, forms, full CRUD, delete confirmation, admin flows
   await BCR_SUITE.run();
   ```

2. Each returns `{ pass, fail }` and a list of any failures.

Last run: **69 unit checks** and **100 UI checks**, all passing, with Lighthouse
scoring **1.0** for accessibility, best practices and SEO. The layout was also
verified at 320 / 360 / 414 / 768 px with no horizontal overflow on any page.

---

## Requirements

A modern browser (Chrome, Edge, Firefox). No frameworks, no build tools, no npm
packages, no internet connection after the first load — the artwork is local SVG
and there are no external fonts or CDNs.

---

## Known limits of a static build

Worth being upfront about, since this is a school/deployment choice:

* **No shared server database.** Accounts and reports are per-browser.
  Everyone "logging in" on the same computer shares one database; a different
  browser or device gets its own.
* **No real multi-user enforcement.** The admin/resident split is enforced
  faithfully *within* a browser, but a determined user can edit localStorage.
  Only a server can make that tamper-proof.
* If you later need genuine multi-user behaviour, the logic is already isolated
  in `store.js` and `auth.js` — pointing them at a hosted API instead of
  localStorage is a contained change, and the views do not need to change.