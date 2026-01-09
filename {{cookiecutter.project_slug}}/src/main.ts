import './style.css';

function init() {
  console.log('Userscript loaded: {{ cookiecutter.project_name }}');

  const container = document.createElement('div');
  container.id = 'my-userscript-container';
  container.innerHTML = `
    <div>Hello from <b>{{ cookiecutter.project_name }}</b>!</div>
    <button id="my-btn">Click me</button>
  `;

  document.body.appendChild(container);

  const btn = container.querySelector('#my-btn');
  if (btn) {
    btn.addEventListener('click', () => {
      alert('Button clicked inside Userscript!');
    });
  }
}

init();
