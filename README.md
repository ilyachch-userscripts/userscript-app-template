# Userscript App Template

Advanced template with Vite, TypeScript, ESLint and GitHub Actions.

## Quick Start

Run this command in your terminal to create a new project:

```bash
curl -s https://raw.githubusercontent.com/ilyachch-userscripts/userscript-app-template/main/setup.sh | bash -s -- "My Script Name"
```

or

```bash
curl -s https://raw.githubusercontent.com/ilyachch-userscripts/userscript-app-template/main/setup.sh | bash -s --
```

## Requirements

- Node.js (v18+)
- Cruft (pip install cruft) - Recommended for template updates
- OR Cookiecutter (pip install cookiecutter) - Fallback
- GitHub CLI (gh) - Optional, for auto-creating repositories

If `gh` is missing, the script will create a local folder with git initialized.

If `cruft` is missing, it will try to use `cookiecutter`.
