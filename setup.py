#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "cookiecutter>=2.6.0",
#   "typer>=0.16.0",
# ]
# ///
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import typer
from cookiecutter.main import cookiecutter

TEMPLATE_REPO_URL = 'https://github.com/ilyachch-userscripts/userscript-app-template'
TEMPLATE_NAME = 'Userscript App'

PREPROCESSED_DYNAMIC_OVERRIDES: dict[str, Any] = {}

RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'
USE_COLOR = sys.stdout.isatty()


def paint(color: str, text: str) -> str:
    if not USE_COLOR:
        return text
    return f'{color}{text}{NC}'


def info(message: str) -> None:
    print(paint(BLUE, message))


def ok(message: str) -> None:
    print(paint(GREEN, message))


def warn(message: str) -> None:
    print(paint(YELLOW, message))


def die(message: str, code: int = 1) -> None:
    print(paint(RED, f'Error: {message}'), file=sys.stderr)
    raise SystemExit(code)


def slugify(value: str) -> str:
    normalized = re.sub(r'[^a-z0-9]+', '-', value.lower())
    normalized = re.sub(r'-{2,}', '-', normalized).strip('-')
    return normalized


def run_cmd(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    dry_run: bool = False,
    capture_output: bool = False,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    cmd_text = ' '.join(shlex.quote(part) for part in cmd)
    if dry_run:
        print(f'+ {cmd_text}')
        return subprocess.CompletedProcess(cmd, 0, '', '')

    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        capture_output=capture_output,
        check=False,
    )
    if check and proc.returncode != 0:
        if proc.stdout:
            print(proc.stdout.rstrip())
        if proc.stderr:
            print(proc.stderr.rstrip(), file=sys.stderr)
        raise subprocess.CalledProcessError(proc.returncode, cmd)
    return proc


@dataclass(frozen=True)
class CliOptions:
    project_name: str | None
    cookiecutter_json: Path
    gh_user: str | None
    dry_run: bool
    dynamic_overrides: dict[str, Any]


def detect_cookiecutter_json(explicit_path: str | None) -> Path:
    if explicit_path:
        path = Path(explicit_path).expanduser().resolve()
        if not path.is_file():
            die(f'cookiecutter.json not found at: {path}')
        return path

    env_path = os.getenv('COOKIECUTTER_JSON_PATH')
    if env_path:
        path = Path(env_path).expanduser().resolve()
        if not path.is_file():
            die(f'cookiecutter.json not found at COOKIECUTTER_JSON_PATH={path}')
        return path

    cwd_candidate = Path.cwd() / 'cookiecutter.json'
    if cwd_candidate.is_file():
        return cwd_candidate.resolve()

    script_candidate = Path(__file__).resolve().with_name('cookiecutter.json')
    if script_candidate.is_file():
        return script_candidate

    die('cookiecutter.json not found (use --cookiecutter-json PATH).')
    raise AssertionError('unreachable')


def load_cookiecutter_defaults(path: Path) -> dict[str, Any]:
    try:
        with path.open('r', encoding='utf-8') as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        die(f'Invalid JSON in {path}: {exc}')
    if not isinstance(data, dict):
        die(f'cookiecutter.json at {path} must contain a JSON object.')
    return data


def flag_name_for_key(key: str) -> str:
    return f'--{key.replace("_", "-")}'


def cookiecutter_env_name(key: str) -> str:
    return key.upper()


def parse_bool(value: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {'1', 'true', 'yes', 'y', 'on'}:
        return True
    if normalized in {'0', 'false', 'no', 'n', 'off'}:
        return False
    die(f'Invalid boolean value: {value!r}')
    raise AssertionError('unreachable')


def coerce_cookiecutter_value(key: str, raw_default: Any, value: Any) -> Any:
    if isinstance(raw_default, bool):
        if isinstance(value, bool):
            return value
        return parse_bool(str(value))

    if isinstance(raw_default, int) and not isinstance(raw_default, bool):
        return int(value)

    if isinstance(raw_default, float):
        return float(value)

    if isinstance(raw_default, list):
        choice = str(value)
        if raw_default:
            choices = [str(item) for item in raw_default]
            if choice not in choices:
                die(
                    f'Invalid value for {flag_name_for_key(key)}: {choice}. '
                    f'Choices: {", ".join(choices)}'
                )
        return choice

    return value


def default_value_for_cookiecutter(raw_default: Any) -> Any:
    if isinstance(raw_default, list):
        return raw_default[0] if raw_default else ''
    return raw_default


def split_dynamic_args(
    tokens: list[str], defaults: dict[str, Any]
) -> tuple[list[str], dict[str, Any]]:
    flag_map = {
        flag_name_for_key(key): key
        for key in defaults
        if key not in {'cookiecutter_json', 'dry_run', 'gh_user'}
    }
    filtered_tokens: list[str] = []
    overrides: dict[str, Any] = {}
    i = 0
    while i < len(tokens):
        token = tokens[i]
        if not token.startswith('--'):
            filtered_tokens.append(token)
            i += 1
            continue

        if token in {'--help', '-h'}:
            filtered_tokens.append(token)
            i += 1
            continue

        if token.startswith('--no-'):
            key = token.removeprefix('--no-').replace('-', '_')
            if key not in defaults or not isinstance(defaults[key], bool):
                filtered_tokens.append(token)
                i += 1
                continue
            overrides[key] = False
            i += 1
            continue

        flag, has_value, inline_value = token.partition('=')
        key = flag_map.get(flag)
        if key is None:
            filtered_tokens.append(token)
            i += 1
            continue

        raw_default = defaults[key]
        if has_value:
            value = inline_value
        elif isinstance(raw_default, bool):
            if i + 1 < len(tokens) and not tokens[i + 1].startswith('--'):
                value = tokens[i + 1]
                i += 1
            else:
                value = True
        else:
            if i + 1 >= len(tokens):
                die(f'Missing value for {flag}')
            value = tokens[i + 1]
            i += 1

        overrides[key] = coerce_cookiecutter_value(key, raw_default, value)
        i += 1

    return filtered_tokens, overrides


def build_contexts(
    options: CliOptions, defaults: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    extra_context: dict[str, Any] = {}
    effective_context: dict[str, Any] = {}

    for key, raw_default in defaults.items():
        if key in options.dynamic_overrides:
            value = options.dynamic_overrides[key]
            extra_context[key] = value
            effective_context[key] = value
            continue

        env_value = os.getenv(cookiecutter_env_name(key))
        if env_value not in (None, ''):
            value = coerce_cookiecutter_value(key, raw_default, env_value)
            extra_context[key] = value
            effective_context[key] = value
            continue

        effective_context[key] = default_value_for_cookiecutter(raw_default)

    if options.project_name and 'project_name' in defaults and 'project_name' not in extra_context:
        extra_context['project_name'] = options.project_name
        effective_context['project_name'] = options.project_name

    if options.gh_user:
        extra_context['github_username'] = options.gh_user
        effective_context['github_username'] = options.gh_user
    elif 'github_username' not in extra_context:
        gh_user_env = os.getenv('GH_USER')
        if gh_user_env:
            extra_context['github_username'] = gh_user_env
            effective_context['github_username'] = gh_user_env

    return extra_context, effective_context


def derive_project_slug(effective_context: dict[str, Any]) -> str:
    slug_candidate = str(effective_context.get('project_slug', '')).strip()
    if slug_candidate and '{{' not in slug_candidate:
        return slug_candidate

    project_name = str(effective_context.get('project_name', '')).strip()
    if not project_name:
        die(
            'project_name is required (use --project-name, positional name, PROJECT_NAME env, or cookiecutter.json).'
        )
    derived = slugify(project_name)
    if not derived:
        die('project_slug could not be derived from project_name.')
    return derived


def has_gh_auth() -> bool:
    if shutil.which('gh') is None:
        return False
    proc = run_cmd(['gh', 'auth', 'status'], check=False, capture_output=True)
    return proc.returncode == 0


def detect_gh_user(effective_context: dict[str, Any], gh_enabled: bool) -> str:
    user = str(effective_context.get('github_username', '')).strip()
    if user:
        return user

    if gh_enabled:
        proc = run_cmd(['gh', 'api', 'user', '-q', '.login'], check=False, capture_output=True)
        if proc.returncode == 0:
            fetched = proc.stdout.strip()
            if fetched:
                return fetched

    proc = run_cmd(['git', 'config', '--get', 'github.user'], check=False, capture_output=True)
    if proc.returncode == 0:
        return proc.stdout.strip()
    return ''


def repo_exists(repo_full: str) -> bool:
    if shutil.which('gh') is None:
        return False
    proc = run_cmd(['gh', 'repo', 'view', repo_full], check=False, capture_output=True)
    return proc.returncode == 0


def repo_slug_from_remote_url(remote_url: str) -> str | None:
    cleaned = remote_url.strip().rstrip('/')
    cleaned = re.sub(r'\.git$', '', cleaned)
    match = re.search(r'github\.com[:/](?P<owner>[^/]+)/(?P<repo>[^/]+)$', cleaned)
    if not match:
        return None
    return f'{match.group("owner")}/{match.group("repo")}'


def is_git_repo(path: Path, dry_run: bool = False) -> bool:
    if dry_run:
        return (path / '.git').exists()
    proc = run_cmd(
        ['git', '-C', str(path), 'rev-parse', '--is-inside-work-tree'],
        check=False,
        capture_output=True,
    )
    return proc.returncode == 0


def get_origin_repo_slug(path: Path, dry_run: bool = False) -> str | None:
    if dry_run:
        return None
    proc = run_cmd(
        ['git', '-C', str(path), 'remote', 'get-url', 'origin'],
        check=False,
        capture_output=True,
    )
    if proc.returncode != 0:
        return None
    return repo_slug_from_remote_url(proc.stdout.strip())


def ensure_remote_checkout(
    repo_full: str, target_dir: Path, dry_run: bool, gh_enabled: bool
) -> None:
    repo_url = f'https://github.com/{repo_full}.git'

    if target_dir.exists():
        if is_git_repo(target_dir, dry_run=dry_run):
            current_slug = get_origin_repo_slug(target_dir, dry_run=dry_run)
            if current_slug == repo_full or dry_run:
                info('Target directory already has the correct git repository. Skipping clone.')
                return
            die(
                f'Target directory already contains a different git repository '
                f'({current_slug or "unknown origin"}).'
            )

        if dry_run:
            print(f'+ git clone {shlex.quote(repo_url)} {shlex.quote(str(target_dir))}')
            return

        has_files = any(target_dir.iterdir())
        if not has_files:
            run_cmd(['git', 'clone', repo_url, str(target_dir)], dry_run=dry_run)
            return

        info('Target directory exists and is not empty; attaching it to the remote repository.')
        run_cmd(['git', 'init'], cwd=target_dir, dry_run=dry_run)
        run_cmd(['git', 'remote', 'add', 'origin', repo_url], cwd=target_dir, dry_run=dry_run)
        run_cmd(['git', 'fetch', 'origin'], cwd=target_dir, dry_run=dry_run, check=False)
        if gh_enabled:
            branch_proc = run_cmd(
                [
                    'gh',
                    'repo',
                    'view',
                    repo_full,
                    '--json',
                    'defaultBranchRef',
                    '-q',
                    '.defaultBranchRef.name',
                ],
                check=False,
                capture_output=True,
                dry_run=dry_run,
            )
            default_branch = branch_proc.stdout.strip() if branch_proc.returncode == 0 else ''
            if default_branch:
                run_cmd(
                    [
                        'git',
                        'checkout',
                        '-B',
                        default_branch,
                        '--track',
                        f'origin/{default_branch}',
                    ],
                    cwd=target_dir,
                    dry_run=dry_run,
                    check=False,
                )
        return

    run_cmd(['git', 'clone', repo_url, str(target_dir)], dry_run=dry_run)


def ensure_local_directory_with_git(target_dir: Path, dry_run: bool) -> None:
    if not target_dir.exists():
        if dry_run:
            print(f'+ mkdir -p {shlex.quote(str(target_dir))}')
        else:
            target_dir.mkdir(parents=True, exist_ok=True)

    if is_git_repo(target_dir, dry_run=dry_run):
        return

    run_cmd(['git', 'init'], cwd=target_dir, dry_run=dry_run)
    run_cmd(['git', 'branch', '-M', 'main'], cwd=target_dir, dry_run=dry_run, check=False)


def detect_template_source() -> str:
    script_dir = Path(__file__).resolve().parent
    cookiecutter_path = script_dir / 'cookiecutter.json'
    has_template_dir = any(
        entry.is_dir() and entry.name.startswith('{{cookiecutter.')
        for entry in script_dir.iterdir()
    )
    if cookiecutter_path.is_file() and has_template_dir:
        return str(script_dir)
    return TEMPLATE_REPO_URL


def apply_template(
    template_source: str,
    output_parent: Path,
    extra_context: dict[str, Any],
    dry_run: bool,
) -> None:
    info('Applying template...')
    if dry_run:
        context_preview = json.dumps(extra_context, ensure_ascii=True, sort_keys=True)
        print(
            f'+ cookiecutter(template={template_source!r}, output_dir={str(output_parent)!r}, extra_context={context_preview})'
        )
        return

    output_parent.mkdir(parents=True, exist_ok=True)
    cookiecutter(
        template_source,
        no_input=True,
        extra_context=extra_context,
        output_dir=str(output_parent),
        overwrite_if_exists=True,
    )


def ensure_origin_if_missing(target_dir: Path, repo_full: str, dry_run: bool) -> None:
    proc = run_cmd(
        ['git', 'remote', 'get-url', 'origin'],
        cwd=target_dir,
        dry_run=dry_run,
        check=False,
        capture_output=not dry_run,
    )
    if proc.returncode == 0:
        return
    run_cmd(
        ['git', 'remote', 'add', 'origin', f'https://github.com/{repo_full}.git'],
        cwd=target_dir,
        dry_run=dry_run,
    )


def finalize_git(
    target_dir: Path,
    *,
    dry_run: bool,
    push: bool,
    repo_full: str | None,
) -> None:
    info('Finalizing git...')
    ensure_local_directory_with_git(target_dir, dry_run=dry_run)

    if repo_full and push:
        ensure_origin_if_missing(target_dir, repo_full, dry_run=dry_run)

    run_cmd(['git', 'add', '.'], cwd=target_dir, dry_run=dry_run)

    status_proc = run_cmd(
        ['git', 'status', '--porcelain'],
        cwd=target_dir,
        dry_run=dry_run,
        capture_output=not dry_run,
        check=False,
    )
    if dry_run or (status_proc.stdout.strip() if status_proc.stdout else True):
        run_cmd(
            ['git', 'commit', '-m', 'Initialize project from template'],
            cwd=target_dir,
            dry_run=dry_run,
            check=False,
        )
    else:
        info('No file changes to commit.')

    if push and repo_full:
        run_cmd(
            ['git', 'push', '-u', 'origin', 'HEAD'], cwd=target_dir, dry_run=dry_run, check=False
        )


def install_deps_if_any(target_dir: Path, dry_run: bool) -> None:
    package_json = target_dir / 'package.json'
    if package_json.is_file() and shutil.which('npm'):
        info('Installing NPM dependencies...')
        run_cmd(['npm', 'install'], cwd=target_dir, dry_run=dry_run)


def run_setup(options: CliOptions) -> int:
    defaults = load_cookiecutter_defaults(options.cookiecutter_json)
    extra_context, effective_context = build_contexts(options, defaults)
    project_slug = derive_project_slug(effective_context)
    project_name = str(effective_context.get('project_name', '')).strip() or project_slug
    target_dir = Path.cwd() / project_slug

    gh_enabled = has_gh_auth()
    gh_user = detect_gh_user(effective_context, gh_enabled) if gh_enabled else ''
    repo_full = f'{gh_user}/{project_slug}' if gh_enabled and gh_user else None

    info(f'=== Initializing new project from template: {TEMPLATE_NAME} ===')
    print(f'Project name: {paint(GREEN, project_name)}')
    print(f'Project slug: {paint(GREEN, project_slug)}')
    if repo_full:
        print(f'GitHub:       {paint(GREEN, f"enabled ({repo_full})")}')
    elif gh_enabled:
        print(
            f'GitHub:       {paint(YELLOW, "gh available, but owner is unknown; remote creation skipped")}'
        )
    else:
        print(f'GitHub:       {paint(YELLOW, "disabled (gh not available or not authenticated)")}')
    if options.dry_run:
        print(f'Mode:         {paint(YELLOW, "dry-run")}')
    print()

    if repo_full:
        exists = repo_exists(repo_full)
        if exists:
            info(f'Repository {repo_full} already exists; skipping creation.')
        else:
            info(f'Creating GitHub repository: {repo_full}')
            run_cmd(['gh', 'repo', 'create', repo_full, '--public'], dry_run=options.dry_run)
        ensure_remote_checkout(repo_full, target_dir, options.dry_run, gh_enabled)
    else:
        ensure_local_directory_with_git(target_dir, options.dry_run)

    template_source = detect_template_source()
    apply_template(
        template_source=template_source,
        output_parent=target_dir.parent,
        extra_context=extra_context,
        dry_run=options.dry_run,
    )
    finalize_git(
        target_dir=target_dir,
        dry_run=options.dry_run,
        push=bool(repo_full),
        repo_full=repo_full,
    )
    install_deps_if_any(target_dir, options.dry_run)

    ok('=== Done! ===')
    if not options.dry_run:
        print(f'Project folder: {paint(BLUE, str(target_dir))}')
    return 0


def main(
    project_name: str | None = typer.Argument(None, help='Positional alias for --project-name'),
    cookiecutter_json: Path | None = typer.Option(
        None, '--cookiecutter-json', help='Path to cookiecutter.json'
    ),
    gh_user: str | None = typer.Option(
        None, '--gh-user', help='GitHub owner for repository creation/check'
    ),
    dry_run: bool = typer.Option(False, '--dry-run', help='Print actions only'),
) -> None:
    cookiecutter_path = detect_cookiecutter_json(
        str(cookiecutter_json) if cookiecutter_json is not None else None
    )
    options = CliOptions(
        project_name=project_name,
        cookiecutter_json=cookiecutter_path,
        gh_user=gh_user or os.getenv('GH_USER'),
        dry_run=dry_run,
        dynamic_overrides=PREPROCESSED_DYNAMIC_OVERRIDES,
    )
    raise SystemExit(run_setup(options))


def get_cookiecutter_json_arg(argv: list[str]) -> str | None:
    for index, token in enumerate(argv):
        if token.startswith('--cookiecutter-json='):
            return token.split('=', 1)[1]
        if token == '--cookiecutter-json' and index + 1 < len(argv):
            return argv[index + 1]
    return None


if __name__ == '__main__':
    raw_argv = sys.argv[1:]
    if '-h' not in raw_argv and '--help' not in raw_argv:
        bootstrap_cookiecutter_json = detect_cookiecutter_json(get_cookiecutter_json_arg(raw_argv))
        bootstrap_defaults = load_cookiecutter_defaults(bootstrap_cookiecutter_json)
        filtered_argv, PREPROCESSED_DYNAMIC_OVERRIDES = split_dynamic_args(
            raw_argv, bootstrap_defaults
        )
        sys.argv = [sys.argv[0], *filtered_argv]
    typer.run(main)
