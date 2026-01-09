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
# Phase 1: Collect all information
# ==========================================

echo -e "${BLUE}=== Initializing new project from template: $TEMPLATE_NAME ===${NC}"

# 1.1 Request project name (if not passed as argument)
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

# 1.2 Check if project folder already exists
if [ -d "$PROJECT_SLUG" ]; then
    echo -e "${RED}Error: Folder '$PROJECT_SLUG' already exists.${NC}"
    exit 1
fi

# 1.3 Check for generator (Cruft or Cookiecutter)
HAS_CRUFT=false
HAS_COOKIECUTTER=false
GENERATOR_TOOL=""
GENERATOR_WARNING=""

if command -v cruft &> /dev/null; then
    HAS_CRUFT=true
    GENERATOR_TOOL="cruft"
elif command -v cookiecutter &> /dev/null; then
    HAS_COOKIECUTTER=true
    GENERATOR_TOOL="cookiecutter"
    GENERATOR_WARNING="Template updates will be unavailable (cruft not installed)"
fi

# 1.4 GitHub CLI Check
HAS_GH=false
GH_USER=""
GH_WARNING=""

if command -v gh &> /dev/null; then
    if gh auth status &> /dev/null; then
        HAS_GH=true
        GH_USER=$(gh api user -q ".login")
        # Check if repository already exists on GitHub
        if gh repo view "ilyachch-userscripts/$PROJECT_SLUG" &> /dev/null; then
            echo -e "${RED}Error: Repository 'ilyachch-userscripts/$PROJECT_SLUG' already exists on GitHub.${NC}"
            exit 1
        fi
    else
        GH_WARNING="gh is installed, but you are not logged in (run: gh auth login)"
    fi
else
    GH_WARNING="GitHub CLI (gh) not found"
fi

# ==========================================
# Phase 2: Show summary and ask for confirmation
# ==========================================

echo -e "\n${BLUE}=== Configuration Summary ===${NC}"
echo -e "Project name: ${GREEN}$PROJECT_NAME${NC}"
echo -e "Project slug: ${GREEN}$PROJECT_SLUG${NC}"
echo ""

# Check if we can proceed at all
if [ -z "$GENERATOR_TOOL" ]; then
    echo -e "${RED}❌ Critical error: Neither cruft nor cookiecutter found.${NC}"
    echo "To run this script, you must install one of these tools."
    echo "Recommended: pip install cruft"
    echo "Alternative: pip install cookiecutter"
    exit 1
fi

# Show generator status
echo -e "Template generator: ${GREEN}$GENERATOR_TOOL${NC}"
if [ -n "$GENERATOR_WARNING" ]; then
    echo -e "   ${YELLOW}⚠ $GENERATOR_WARNING${NC}"
fi

# Show GitHub status
if [ "$HAS_GH" = true ]; then
    echo -e "GitHub: ${GREEN}Available (user: $GH_USER)${NC}"
    echo -e "   → Will create remote repository: ilyachch-userscripts/$PROJECT_SLUG"
    echo -e "   → Will clone it locally and apply template"
else
    echo -e "GitHub: ${RED}Not available${NC}"
    if [ -n "$GH_WARNING" ]; then
        echo -e "   ${YELLOW}⚠ $GH_WARNING${NC}"
    fi
    echo -e "   → Will create local folder and git repository only"
fi

echo ""

# Ask for confirmation if there are any limitations
if [ -n "$GENERATOR_WARNING" ] || [ "$HAS_GH" = false ]; then
    echo -e "${YELLOW}There are some limitations. Do you want to continue? [y/N]${NC}"
    read -r CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborted by user.${NC}"
        exit 0
    fi
fi

# ==========================================
# Phase 3: Execute changes
# ==========================================

echo -e "\n${BLUE}🚀 Starting project generation...${NC}"

# --- Step 3.1: Create Repository (if GH available) ---
if [ "$HAS_GH" = true ]; then
    echo -e "Creating GitHub repository and cloning..."
    # --clone flag creates the directory and initializes git
    if gh repo create "ilyachch-userscripts/$PROJECT_SLUG" --public --clone; then
        echo -e "${GREEN}✅ Repository created and cloned!${NC}"
    else
        echo -e "${RED}❌ Failed to create repository.${NC}"
        exit 1
    fi
else
    echo "Skipping GitHub creation (gh not available). Proceeding with local generation."
fi

# --- Step 3.2: Apply Template ---
echo -e "Applying template..."

# Form JSON with parameters to avoid manual input
EXTRA_CONTEXT="{\"project_name\": \"$PROJECT_NAME\", \"project_slug\": \"$PROJECT_SLUG\"}"
if [ "$HAS_GH" = true ]; then
    EXTRA_CONTEXT="${EXTRA_CONTEXT%?}, \"github_username\": \"$GH_USER\"}"
fi

# Note: We MUST use --overwrite-if-exists (cruft) or -f (cookiecutter)
# because if GH created the repo, the folder now exists.
if [ "$HAS_CRUFT" = true ]; then
    cruft create "$TEMPLATE_REPO_URL" --extra-context "$EXTRA_CONTEXT" --no-input --overwrite-if-exists
else
    cookiecutter "$TEMPLATE_REPO_URL" --extra-context "$EXTRA_CONTEXT" --no-input -f
fi

# Check if folder exists (it should by now)
if [ ! -d "$PROJECT_SLUG" ]; then
    echo -e "${RED}Error: Project folder not found after generation.${NC}"
    exit 1
fi

cd "$PROJECT_SLUG" || exit

# --- Step 3.3: Finalize Git ---
echo -e "\n${BLUE}🔧 Finalizing Git configuration...${NC}"

if [ "$HAS_GH" = true ]; then
    # We are already inside a git repo (from clone).
    # We just need to commit the template files.
    echo "Adding template files to git..."
    git add .
    git commit -m "Initialize project from template"

    echo "Pushing to remote..."
    git push origin HEAD
    echo -e "${GREEN}✅ Code pushed to GitHub!${NC}"
else
    # Local only scenario (folder created by cruft, no git yet)
    if [ ! -d ".git" ]; then
        git init
        git branch -M main
    fi
    echo "Performing local commit..."
    git add .
    git commit -m "Initial commit from template"
    echo -e "${GREEN}✅ Local project ready (without remote repository).${NC}"
fi

# Install dependencies (if package.json exists)
if [ -f "package.json" ]; then
    echo -e "\n${BLUE}📦 Installing NPM dependencies...${NC}"
    npm install
fi

echo -e "\n${GREEN}=== Done! ===${NC}"
echo -e "Project folder: ${BLUE}$(pwd)${NC}"
if [ "$HAS_GH" = false ]; then
    echo -e "${YELLOW}Don't forget to create the repository manually or install gh cli!${NC}"
fi
