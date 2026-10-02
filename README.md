# heath-apps
Each top-level folder that contains an `index.html` is an app. Push to `main` and it is built, run in Docker on its own
port and published in Pangolin as `<folder>.<your domain>`. Optional `<folder>/app.env`: `SUBDOMAIN=...`, `TITLE=...`.
Changing `Dockerfile`, `nginx/` or `deploy/` redeploys everything. Run the workflow manually with "all" to force a full rebuild.
