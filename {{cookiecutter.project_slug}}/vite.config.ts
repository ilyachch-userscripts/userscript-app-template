import { defineConfig } from 'vite';
import monkey from 'vite-plugin-monkey';

// === Configuration ===
const SCRIPT_NAME = '{{ cookiecutter.project_name }}';
const NAMESPACE = 'https://github.com/{{ cookiecutter.github_username }}';
const MATCH_URLS = ['*://*/*'];
const ICON_URL = 'https://www.google.com/s2/favicons?sz=64&domain=github.com';
// =====================

export default defineConfig({
  plugins: [
    monkey({
      entry: 'src/main.ts',
      userscript: {
        name: SCRIPT_NAME,
        namespace: NAMESPACE,
        match: MATCH_URLS,
        icon: ICON_URL,
        description: '{{ cookiecutter.description }}',
        author: '{{ cookiecutter.author }}',
        grant: ['GM_addStyle'],
        homepageURL: 'https://github.com/{{ cookiecutter.github_username }}/{{ cookiecutter.project_slug }}',
        supportURL: 'https://github.com/{{ cookiecutter.github_username }}/{{ cookiecutter.project_slug }}/issues',
        updateURL: 'https://github.com/{{ cookiecutter.github_username }}/{{ cookiecutter.project_slug }}/releases/latest/download/{{ cookiecutter.project_slug }}.user.js',
        downloadURL: 'https://github.com/{{ cookiecutter.github_username }}/{{ cookiecutter.project_slug }}/releases/latest/download/{{ cookiecutter.project_slug }}.user.js',
        fileName: '{{ cookiecutter.project_slug }}.user.js',
        'run-at': '{{ cookiecutter.run_at }}',
      },
    }),
  ],
});
