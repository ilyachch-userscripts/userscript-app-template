#!/bin/bash

# ==========================================
# Settings (Set these for each template)
# ==========================================
TEMPLATE_REPO_URL="https://github.com/ilyachch-userscripts/userscript-app-template"
TEMPLATE_NAME="Userscript App"

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==========================================
# Logic
# ==========================================

echo -e "${BLUE}=== Initializing new project from template: $TEMPLATE_NAME ===${NC}"

# 1. Request project name (if not passed as argument)
PROJECT_NAME="$1"
if [ -z "$PROJECT_NAME" ]; then
    echo -e "${YELLOW}Enter project name (e.g., 'My Cool Script'):${NC}"
    read PROJECT_NAME
fi

if [ -z "$PROJECT_NAME" ]; then
    echo -e "${RED}Error: Project name cannot be empty.${NC}"
    exit 1
fi

PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# 2. Check for generator (Cruft or Cookiecutter)
HAS_CRUFT=false
HAS_COOKIECUTTER=false

if command -v cruft &> /dev/null; then
    HAS_CRUFT=true
elif command -v cookiecutter &> /dev/null; then
    HAS_COOKIECUTTER=true
else
    echo -e "${RED}Critical error: Neither cruft nor cookiecutter found.${NC}"
    echo "To run this script, you must install one of these tools."
    echo "Recommended: pip install cruft"
    echo "Alternative: pip install cookiecutter"
    exit 1
fi

# 3. GitHub CLI Check
HAS_GH=false
if command -v gh &> /dev/null; then
    HAS_GH=true
    # Check login status
    if ! gh auth status &> /dev/null; then
        echo -e "${YELLOW}Warning: gh is installed, but you are not logged in (gh auth login). Running in local mode.${NC}"
        HAS_GH=false
    fi
else
    echo -e "${YELLOW}Warning: GitHub CLI (gh) not found. GitHub repository will not be created automatically.${NC}"
fi

# 4. Create project
echo -e "\n${BLUE}🚀 Generating project...${NC}"

# Form JSON with parameters to avoid manual input
EXTRA_CONTEXT="{\"project_name\": \"$PROJECT_NAME\", \"project_slug\": \"$PROJECT_SLUG\"}"
# If gh exists, try to guess username, otherwise use placeholder
if [ "$HAS_GH" = true ]; then
    GH_USER=$(gh api user -q ".login")
    EXTRA_CONTEXT="${EXTRA_CONTEXT%?}, \"github_username\": \"$GH_USER\"}"
fi

if [ "$HAS_CRUFT" = true ]; then
    cruft create "$TEMPLATE_REPO_URL" --extra-context "$EXTRA_CONTEXT" --no-input --overwrite-if-exists
else
    echo -e "${YELLOW}Cruft not found, using cookiecutter (template updates will be unavailable).${NC}"
    cookiecutter "$TEMPLATE_REPO_URL" --extra-context "$EXTRA_CONTEXT" --no-input --overwrite-if-exists
fi

if [ ! -d "$PROJECT_SLUG" ]; then
    echo -e "${RED}Error: Project folder was not created.${NC}"
    exit 1
fi

cd "$PROJECT_SLUG" || exit

# 5. Git and GitHub Initialization
echo -e "\n${BLUE}🔧 Configuring Git...${NC}"

# If this is a fresh folder, git might not be there (cookiecutter doesn't create it)
if [ ! -d ".git" ]; then
    git init
    git branch -M main
fi

if [ "$HAS_GH" = true ]; then
    echo "Creating GitHub repository..."
    # Attempting to create. If name is taken — warn, but don't fail
    if gh repo create "ilyachch-userscripts/$PROJECT_SLUG" --public --source=. --remote=origin --push; then
        echo -e "${GREEN}✅ Repository created and code pushed!${NC}"
    else
        echo -e "${RED}❌ Failed to create repository (name might be taken).${NC}"
        echo "Local git initialized."
    fi
else
    echo "Performing local commit..."
    git add .
    git commit -m "Initial commit from template"
    echo -e "${GREEN}✅ Local project ready (without remote repository).${NC}"
fi

# 6. Install dependencies (if package.json exists)
if [ -f "package.json" ]; then
    echo -e "\n${BLUE}📦 Installing NPM dependencies...${NC}"
    npm install
fi

echo -e "\n${GREEN}=== Done! ===${NC}"
echo -e "Project folder: ${BLUE}$(pwd)${NC}"
if [ "$HAS_GH" = false ]; then
    echo -e "${YELLOW}Don't forget to create the repository manually or install gh cli!${NC}"
fi
