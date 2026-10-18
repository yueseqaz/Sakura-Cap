document.documentElement.classList.add('js');

const tabs = [...document.querySelectorAll('.experience-tab')];
const panels = [...document.querySelectorAll('.experience-panel')];

function activateTab(tab, focus = false) {
  tabs.forEach(item => {
    const active = item === tab;
    item.classList.toggle('active', active);
    item.setAttribute('aria-selected', String(active));
    item.tabIndex = active ? 0 : -1;
  });
  panels.forEach(panel => {
    const active = panel.id === `panel-${tab.dataset.panel}`;
    panel.hidden = !active;
    panel.classList.toggle('active', active);
  });
  if (focus) tab.focus();
}

tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => activateTab(tab));
  tab.addEventListener('keydown', event => {
    const direction = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
    if (!direction && event.key !== 'Home' && event.key !== 'End') return;
    event.preventDefault();
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (index + direction + tabs.length) % tabs.length;
    activateTab(tabs[next], true);
  });
});

if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.08, rootMargin: '0px 0px -30px 0px' });
  document.querySelectorAll('.reveal').forEach(element => observer.observe(element));
} else {
  document.querySelectorAll('.reveal').forEach(element => element.classList.add('visible'));
}

const copyButton = document.querySelector('[data-copy]');
copyButton?.addEventListener('click', async () => {
  const original = copyButton.textContent;
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(copyButton.dataset.copy);
    } else {
      const field = document.createElement('textarea');
      field.value = copyButton.dataset.copy;
      field.style.cssText = 'position:fixed;opacity:0';
      document.body.append(field);
      field.select();
      if (!document.execCommand('copy')) throw new Error('Copy failed');
      field.remove();
    }
    copyButton.textContent = '已复制';
  } catch {
    copyButton.textContent = '复制失败';
  }
  setTimeout(() => { copyButton.textContent = original; }, 1800);
});

const compare = document.querySelector('.comparison');
const compareRange = document.querySelector('#compare-range');
compareRange?.addEventListener('input', () => {
  compare.style.setProperty('--split', `${compareRange.value}%`);
});

const nav = document.querySelector('.nav');
const navLinks = [...document.querySelectorAll('.nav-links a[href^="#"]')];
let scrollQueued = false;
function updatePagePosition() {
  const height = document.documentElement.scrollHeight - innerHeight;
  nav.style.setProperty('--scroll-progress', `${height > 0 ? scrollY / height * 100 : 0}%`);
  let active = '';
  navLinks.forEach(link => {
    const section = document.querySelector(link.getAttribute('href'));
    if (section && section.getBoundingClientRect().top <= 170) active = link.getAttribute('href');
  });
  navLinks.forEach(link => {
    const current = link.getAttribute('href') === active;
    link.classList.toggle('current', current);
    if (current) link.setAttribute('aria-current', 'location');
    else link.removeAttribute('aria-current');
  });
  scrollQueued = false;
}
window.addEventListener('scroll', () => {
  if (!scrollQueued) {
    requestAnimationFrame(updatePagePosition);
    scrollQueued = true;
  }
}, { passive: true });
window.addEventListener('resize', updatePagePosition);
updatePagePosition();
