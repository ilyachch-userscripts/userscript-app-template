#!/usr/bin/env bash
set -Eeuo pipefail

TEMPLATE_REPO_URL="https://github.com/ilyachch-userscripts/userscript-app-template"
TEMPLATE_NAME="Userscript App"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

DRY_RUN=false

PROJECT_NAME="${PROJECT_NAME:-}"
PROJECT_SLUG="${PROJECT_SLUG:-}"
GH_USER="${GH_USER:-}"
COOKIECUTTER_JSON_PATH="${COOKIECUTTER_JSON_PATH:-}"

GENERATOR_TOOL=""
HAS_GH=false

info()  { echo -e "${BLUE}$*${NC}"; }
ok()    { echo -e "${GREEN}$*${NC}"; }
warn()  { echo -e "${YELLOW}$*${NC}"; }
err()   { echo -e "${RED}$*${NC}" >&2; }
die()   { err "Error: $*"; exit 1; }

run() {
  if $DRY_RUN; then
    echo "+ $*"
  else
    "$@"
  fi
}

usage() {
  cat <<'USAGE'
Usage:
  setup.sh [--project-name NAME] [--project-slug SLUG] [--gh-user USER]
           [--cookiecutter-json PATH] [--dry-run] [--help]

Resolution order:
  args -> environment -> cookiecutter.json (if available) -> git/gh -> defaults

Environment variables:
  PROJECT_NAME, PROJECT_SLUG, GH_USER, COOKIECUTTER_JSON_PATH
USAGE
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

slugify() {
  local s="${1:-}"
  s="$(echo "$s" | tr '[:upper:]' '[:lower:]')"
  s="$(echo "$s" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  echo "$s"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-name) PROJECT_NAME="${2:-}"; shift 2 ;;
      --project-slug) PROJECT_SLUG="${2:-}"; shift 2 ;;
      --gh-user)      GH_USER="${2:-}"; shift 2 ;;
      --cookiecutter-json) COOKIECUTTER_JSON_PATH="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      --help|-h) usage; exit 0 ;;
      *)
        die "Unknown argument: $1 (use --help)"
        ;;
    esac
  done
}

detect_cookiecutter_json() {
  if [[ -n "${COOKIECUTTER_JSON_PATH:-}" ]]; then
    [[ -f "$COOKIECUTTER_JSON_PATH" ]] || die "cookiecutter.json not found at: $COOKIECUTTER_JSON_PATH"
    return 0
  fi

  if [[ -f "./cookiecutter.json" ]]; then
    COOKIECUTTER_JSON_PATH="./cookiecutter.json"
    return 0
  fi

  local script_dir=""
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$script_dir/cookiecutter.json" ]]; then
    COOKIECUTTER_JSON_PATH="$script_dir/cookiecutter.json"
    return 0
  fi

  COOKIECUTTER_JSON_PATH=""
}

json_get() {
  local file="$1"
  local key="$2"

  if have_cmd jq; then
    jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null || true
    return 0
  fi

  if have_cmd python3; then
    python3 - <<PY 2>/dev/null || true
import json, sys
p = ${file@Q}
k = ${key@Q}
try:
    with open(p, "r", encoding="utf-8") as f:
        d = json.load(f)
    v = d.get(k, "")
    if v is None:
        v = ""
    if isinstance(v, (dict, list)):
        v = ""
    print(v)
except Exception:
    pass
PY
    return 0
  fi

  echo ""
}

load_from_cookiecutter_json() {
  [[ -n "${COOKIECUTTER_JSON_PATH:-}" ]] || return 0

  local v=""

  if [[ -z "${PROJECT_NAME:-}" ]]; then
    v="$(json_get "$COOKIECUTTER_JSON_PATH" "project_name")"
    [[ -n "$v" ]] && PROJECT_NAME="$v"
  fi

  if [[ -z "${GH_USER:-}" ]]; then
    v="$(json_get "$COOKIECUTTER_JSON_PATH" "github_username")"
    [[ -n "$v" ]] && GH_USER="$v"
  fi

  if [[ -z "${PROJECT_SLUG:-}" ]]; then
    v="$(json_get "$COOKIECUTTER_JSON_PATH" "project_slug")"
    if [[ -n "$v" && "$v" != *"{{"* ]]; then
      PROJECT_SLUG="$v"
    fi
  fi
}

try_get_gh_user() {
  if [[ -n "${GH_USER:-}" ]]; then
    return 0
  fi

  if have_cmd gh && gh auth status >/dev/null 2>&1; then
    local u=""
    u="$(gh api user -q ".login" 2>/dev/null || true)"
    [[ -n "$u" ]] && GH_USER="$u"
  fi

  if [[ -z "${GH_USER:-}" ]]; then
    GH_USER="$(git config --get github.user 2>/dev/null || true)"
  fi
}

detect_generator() {
  if have_cmd cruft; then
    GENERATOR_TOOL="cruft"
    return 0
  fi
  if have_cmd cookiecutter; then
    GENERATOR_TOOL="cookiecutter"
    return 0
  fi
  die "Neither 'cruft' nor 'cookiecutter' found. Install one of them."
}

detect_github() {
  if have_cmd gh && gh auth status >/dev/null 2>&1; then
    HAS_GH=true
  else
    HAS_GH=false
  fi
}

ensure_values() {
  if [[ -z "${PROJECT_NAME:-}" ]]; then
    die "PROJECT_NAME is required (use --project-name or env PROJECT_NAME or cookiecutter.json)."
  fi

  if [[ -z "${PROJECT_SLUG:-}" ]]; then
    PROJECT_SLUG="$(slugify "$PROJECT_NAME")"
  fi

  if [[ -z "${PROJECT_SLUG:-}" ]]; then
    die "PROJECT_SLUG could not be derived."
  fi
}

check_local_folder() {
  if [[ -d "$PROJECT_SLUG" ]]; then
    die "Folder '$PROJECT_SLUG' already exists."
  fi
}

check_remote_repo_conflict() {
  $HAS_GH || return 0

  try_get_gh_user
  if [[ -z "${GH_USER:-}" ]]; then
    warn "GitHub is available, but GH_USER is not detected; remote repo will not be created."
    HAS_GH=false
    return 0
  fi

  if gh repo view "$GH_USER/$PROJECT_SLUG" >/dev/null 2>&1; then
    die "Repository '$GH_USER/$PROJECT_SLUG' already exists on GitHub."
  fi
}

print_summary() {
  info "=== Initializing new project from template: $TEMPLATE_NAME ==="
  echo -e "Project name: ${GREEN}${PROJECT_NAME}${NC}"
  echo -e "Project slug: ${GREEN}${PROJECT_SLUG}${NC}"
  echo -e "Generator:    ${GREEN}${GENERATOR_TOOL}${NC}"
  if $HAS_GH; then
    local user="${GH_USER:-}"
    [[ -n "$user" ]] && echo -e "GitHub:       ${GREEN}enabled${NC} (user: $user)" || echo -e "GitHub:       ${GREEN}enabled${NC}"
  else
    echo -e "GitHub:       ${YELLOW}disabled${NC}"
  fi
  $DRY_RUN && echo -e "Mode:         ${YELLOW}dry-run${NC}"
  echo ""
}

make_extra_context() {
  local ctx
  ctx="{\"project_name\": \"${PROJECT_NAME}\", \"project_slug\": \"${PROJECT_SLUG}\""
  if $HAS_GH && [[ -n "${GH_USER:-}" ]]; then
    ctx="${ctx}, \"github_username\": \"${GH_USER}\""
  fi
  ctx="${ctx}}"
  echo "$ctx"
}

create_repo_and_clone_if_needed() {
  $HAS_GH || return 0
  [[ -n "${GH_USER:-}" ]] || return 0

  info "Creating GitHub repository and cloning..."
  run gh repo create "$GH_USER/$PROJECT_SLUG" --public --clone
  ok "Repository created and cloned."
}

apply_template() {
  info "Applying template..."
  local extra_context
  extra_context="$(make_extra_context)"

  if [[ "$GENERATOR_TOOL" == "cruft" ]]; then
    run cruft create "$TEMPLATE_REPO_URL" \
      --extra-context "$extra_context" \
      --no-input \
      --overwrite-if-exists
  else
    run cookiecutter "$TEMPLATE_REPO_URL" \
      --extra-context "$extra_context" \
      --no-input \
      -f
  fi
}

enter_project_dir_or_die() {
  if [[ ! -d "$PROJECT_SLUG" ]]; then
    die "Project folder not found after generation: $PROJECT_SLUG"
  fi
  run cd "$PROJECT_SLUG"
}

finalize_git() {
  info "Finalizing git..."
  if $HAS_GH && [[ -n "${GH_USER:-}" ]]; then
    run git add .
    run git commit -m "Initialize project from template"
    run git push origin HEAD
    ok "Code pushed to GitHub."
    return 0
  fi

  if [[ ! -d ".git" ]]; then
    run git init
    run git branch -M main
  fi
  run git add .
  run git commit -m "Initial commit from template"
  ok "Local project ready."
}

install_deps_if_any() {
  if [[ -f "package.json" ]] && have_cmd npm; then
    info "Installing NPM dependencies..."
    run npm install
  fi
}

main() {
  parse_args "$@"
  detect_cookiecutter_json
  load_from_cookiecutter_json
  detect_generator
  detect_github
  try_get_gh_user
  ensure_values
  check_local_folder
  check_remote_repo_conflict
  print_summary

  create_repo_and_clone_if_needed
  apply_template
  enter_project_dir_or_die
  finalize_git
  install_deps_if_any

  ok "=== Done! ==="
  if $DRY_RUN; then
    warn "Dry-run mode: no changes were applied."
  else
    echo -e "Project folder: ${BLUE}$(pwd)${NC}"
  fi
}

main "$@"
