import { defineConfig } from 'vite';
import monkey from 'vite-plugin-monkey';

export default defineConfig({
  plugins: [
    monkey({
      entry: 'src/main.ts',
      userscript: {
        name: '{{ cookiecutter.project_name }}',
        namespace: 'https://github.com/{{ cookiecutter.github_username }}',
        match: ['*://*/*'], // Можно вынести в переменную, если нужно
        icon: 'https://www.google.com/s2/favicons?sz=64&domain=github.com',
        description: '{{ cookiecutter.description }}',
        author: '{{ cookiecutter.author }}',
        // Ссылки на релизы GitHub
        updateURL: 'https://github.com/{{ cookiecutter.github_username }}/{{ cookiecutter.project_slug }}/releases/latest/download/{{ cookiecutter.project_slug }}.user.js',
        downloadURL: 'https://github.com/{{ cookiecutter.github_username }}/{{ cookiecutter.project_slug }}/releases/latest/download/{{ cookiecutter.project_slug }}.user.js',
      },
    }),
  ],
});
