(() => {
  'use strict';
  const busy = new WeakSet();
  const watched = new WeakSet();
  const pending = new Set(['unprepared', 'pending', 'processing']);

  function endpoint(action, id) {
    const url = new URL('./', window.location.href);
    url.search = new URLSearchParams({ c: 'localReader', a: action, id });
    return url;
  }

  function updateReader(element, data) {
    const row = element.closest('.flux');
    const template = document.createElement('template');
    template.innerHTML = data.fragment;
    const replacement = template.content.firstElementChild;
    if (!replacement) throw new Error('阅读版响应缺少正文');
    element.replaceWith(replacement);
    if (row && data.title) {
      for (const heading of row.querySelectorAll('.flux_header a.title, .flux_content header h1.title a')) {
        heading.textContent = data.title;
      }
    }
    observe(replacement);
  }

  async function prepare(element, retry = false) {
    if (busy.has(element) || !element.isConnected || document.hidden) return;
    busy.add(element);
    const status = element.dataset.readerStatus;
    const isPost = retry || status === 'unprepared';
    try {
      const options = { credentials: 'same-origin', cache: 'no-store' };
      if (isPost) {
        options.method = 'POST';
        options.body = new URLSearchParams({ _csrf: element.dataset.readerCsrf, retry: retry ? '1' : '0' });
      }
      const response = await fetch(endpoint(isPost ? 'prepare' : 'status', element.dataset.readerId), options);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      updateReader(element, await response.json());
    } catch (error) {
      const notice = element.querySelector('.local-reader-notice');
      if (notice) {
        notice.textContent = `阅读版连接失败（${error.message}），请刷新页面后重试。`;
      }
    } finally {
      busy.delete(element);
    }
  }

  const visible = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (entry.isIntersecting && pending.has(entry.target.dataset.readerStatus)) {
        visible.unobserve(entry.target);
        const delay = entry.target.dataset.readerStatus === 'unprepared' ? 0 : 5000;
        window.setTimeout(() => prepare(entry.target), delay);
      }
    }
  });

  function observe(element) {
    if (watched.has(element)) return;
    watched.add(element);
    if (pending.has(element.dataset.readerStatus)) visible.observe(element);
  }

  function scan(root) {
    if (root instanceof Element && root.matches('.local-reader')) observe(root);
    root.querySelectorAll?.('.local-reader').forEach(observe);
  }

  document.addEventListener('click', event => {
    const button = event.target.closest?.('.local-reader-retry');
    if (button) {
      event.preventDefault();
      prepare(button.closest('.local-reader'), true);
    }
  });
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) {
      document.querySelectorAll('.local-reader').forEach(element => {
        if (pending.has(element.dataset.readerStatus)) visible.observe(element);
      });
    }
  });
  function start() {
    scan(document);
    new MutationObserver(records => {
      for (const record of records) record.addedNodes.forEach(scan);
    }).observe(document.body, { childList: true, subtree: true });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();
