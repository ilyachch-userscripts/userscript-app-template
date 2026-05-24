# Userscript App Template

Advanced template with Vite, TypeScript, ESLint and GitHub Actions.

## Quick Start

Run this command in your terminal to create a new project:

```bash
uv run /path/to/userscript-app-template/setup.py --project-name "My Script Name"
```

or

```bash
curl -fsSL https://raw.githubusercontent.com/ilyachch-userscripts/userscript-app-template/main/setup.py -o /tmp/userscript-template-setup.py
uv run /tmp/userscript-template-setup.py --project-name "My Script Name"
```

## Requirements

- Node.js (v18+)
- `uv` (installs Python dependencies from the script metadata automatically)
- Typer-powered CLI
- GitHub CLI (`gh`) - Optional, for auto-creating repositories

If `gh` is missing (or not authenticated), the script skips GitHub repository creation and initializes a local git repository.

All keys from `cookiecutter.json` are accepted as CLI flags automatically (`key_name` -> `--key-name`) and can also be provided through environment variables (`KEY_NAME`).
