# POS System on Render + Supabase

## 1. Files to upload to GitHub

Upload these files to the **root of one GitHub repository**:

```text
index.php
index.php.php
Dockerfile
render.yaml
.dockerignore
.gitignore
.env.example
README.md
uploads/shop/.htaccess
uploads/shop/index.html
```

Do not upload `.env`, real passwords, API keys, or local `uploads/products`
files. The application entrypoint is `index.php`; `index.php.php` is only a
compatibility wrapper.

## 2. Supabase: fresh database

No SQL file needs to be pasted into Supabase for a new empty project.
`index.php` runs `installDB()` automatically on the first request and creates
all tables in PostgreSQL.

In Supabase:

1. Create a project.
2. Open **Connect**.
3. Select **Session pooler** (or Direct connection).
4. Copy the PostgreSQL connection URI.
5. Keep `sslmode=require` in the URI.

Example format only (do not use this literal value):

```text
postgresql://postgres:YOUR_PASSWORD@db.YOUR_PROJECT_REF.supabase.co:5432/postgres?sslmode=require
```

After deployment, verify the tables in Supabase **Table Editor**. You should
see tables such as `users`, `products`, `transactions`, `stores`, and
`settings`.

## 3. Render environment variables

Create a Render **Web Service** from the GitHub repository and choose Docker.
Use the included `render.yaml`, or enter these variables manually:

```text
DATABASE_URL=PASTE_YOUR_SUPABASE_CONNECTION_URI_HERE
BREVO_API_KEY=PASTE_YOUR_BREVO_KEY_HERE
BREVO_SENDER_EMAIL=your-verified-sender@example.com
BREVO_SENDER_NAME=Pangga Store
```

Never put the real values in GitHub files. The included Render disk must mount
at `/var/www/html/uploads`; otherwise product photos and the shop logo disappear
after a restart or redeploy.

## 4. Existing MySQL database

For existing data, `installDB()` creates/upgrades the PostgreSQL structure but
does not copy MySQL rows. Export MySQL, convert/import the data into Supabase,
preserve numeric IDs, and reset PostgreSQL identity sequences. Also copy
existing uploaded files to the Render persistent disk. Test users, products,
stock, sales, settings, and password reset before switching production traffic.
