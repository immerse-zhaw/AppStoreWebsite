# IMMERSE Projects Website

This website lists IMMERSE repositories with description, download links, and optional preview GIFs.

## How to Add a New Project

1. **Edit `docs/projects.json`**
   Add a new entry for your repo. You can either use the full path (`owner/repo`) or, if all repos are under the same org (e.g. `IMMERSE`), just the repo name.
   Example:

   ```json
   [
     { "repo": "IMMERSE/BracesNotebook", "web": "https://immerse.zhaw.ch/bracesnotebook" },
     { "repo": "IMMERSE/AnimationRigging" }
   ]
   ```

   * `repo`: GitHub repository name (required)
   * `web`: Optional link to a Unity WebGL build

2. **(Optional) Add a preview GIF**
   If you want a preview shown on the site:

   * Place a GIF named `<RepoName>Demo.gif` in `docs/assets/`
     Example:

     ```
     docs/assets/BracesNotebookDemo.gif
     docs/assets/AnimationRiggingDemo.gif
     ```
   * The website will automatically pick it up and show a “Show Preview” button.

3. **Create a GitHub Personal Access Token (PAT)**
   The script needs access to the Enterprise API to fetch repo metadata and releases.

   * Go to your Enterprise GitHub:
     **Profile → Settings → Developer settings → Personal access tokens (classic)**
   * Click **Generate new token (classic)**
   * Select scopes:

     * `repo` (to access private repos)
     * `read:packages` (if needed for assets)
   * Copy the token and save it somewhere secure.

   Then export it in your shell before running the script:

   ```bash
   export SITE_TOKEN=ghp_yourGeneratedTokenHere
   ```

4. **Build the site data**
   Run the script to update `site-data.json`:

   ```bash
   bash docs/scripts/build-site-data.sh
   ```

   This fetches:

   * The repo’s README first paragraph (used as description)
   * The latest release download links (macOS/Windows)
   * The repo URL
   * The optional preview GIF

5. **Open the website locally**
   You need a local web server (file:// won’t work). The simplest is:

   ```bash
   cd docs
   python3 -m http.server 8080
   ```

   Then open [http://localhost:8080](http://localhost:8080).

6. **Deploy**
   Commit and push the changes (`projects.json`, `site-data.json`, and any GIFs).
   The site will update once the branch is deployed (e.g. via GitHub Pages or your internal hosting).