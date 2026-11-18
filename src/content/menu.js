(function () {
  'use strict';

  const ns = window.SlashCmd;
  const s = ns.state;

  let tracking = false;
  let anchor = null; // where we last sat relative to GitHub's menu, kept if it closes
  // Where GitHub's menu sat relative to the "/" the last time we saw it, per textarea, so that
  // when we show without waiting for it we can still sit where it would have been.
  const memory = new WeakMap();
  let remembered = false; // whether this session has recorded `memory` yet

  // How long to wait for GitHub's menu before giving up on showing ours.
  const REVEAL_TIMEOUT_MS = 1000;
  let sessionStart = 0;

  function ensureMenu() {
    if (s.menu) return s.menu;
    s.menu = document.createElement('ul');
    s.menu.className = 'slash-cmd-menu';
    s.menu.setAttribute('role', 'listbox');
    // Shown as the header strip, and what screen readers announce for the list.
    s.menu.setAttribute('aria-label', 'Bot commands');
    s.menu.style.display = 'none';
    // mousedown (not click) so the textarea keeps focus
    s.menu.addEventListener('mousedown', (e) => {
      const li = e.target.closest('li');
      if (!li) return;
      e.preventDefault();
      const ignore = e.target.closest('.slash-cmd-ignore');
      if (ignore) ns.ignore(ignore.dataset.command);
      else ns.accept(Number(li.dataset.index));
    });
    document.body.appendChild(s.menu);
    return s.menu;
  }

  // Pixel position of the text at `index` (the caret by default), via a hidden mirror of the textarea.
  function caretRect(ta, index = ta.selectionStart) {
    const cs = getComputedStyle(ta);
    const mirror = document.createElement('div');
    for (const p of [
      'boxSizing', 'width', 'fontFamily', 'fontSize', 'fontWeight', 'fontStyle',
      'letterSpacing', 'lineHeight', 'textTransform', 'wordSpacing', 'textIndent',
      'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
      'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth',
      'tabSize',
    ]) mirror.style[p] = cs[p];
    Object.assign(mirror.style, {
      position: 'absolute', visibility: 'hidden', top: '0', left: '-9999px',
      whiteSpace: 'pre-wrap', wordWrap: 'break-word', overflow: 'hidden',
    });
    mirror.textContent = ta.value.slice(0, index);
    const marker = document.createElement('span');
    marker.textContent = '​';
    mirror.appendChild(marker);
    document.body.appendChild(mirror);
    const taRect = ta.getBoundingClientRect();
    const left = taRect.left + marker.offsetLeft - ta.scrollLeft;
    const top = taRect.top + marker.offsetTop - ta.scrollTop;
    const lineHeight = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.4;
    mirror.remove();
    return { left, top, lineHeight };
  }

  function render() {
    const m = ensureMenu();
    m.textContent = '';
    m.setAttribute('aria-label', s.heading);
    s.matches.forEach((c, i) => {
      const li = document.createElement('li');
      li.className = 'slash-cmd-item';
      li.setAttribute('role', 'option');
      li.dataset.index = String(i);
      const isSelected = s.zone === 'ours' && i === s.selected;
      li.classList.toggle('is-selected', isSelected);
      li.setAttribute('aria-selected', String(isSelected));
      const name = document.createElement('span');
      name.className = 'slash-cmd-name';
      name.textContent = c.label;
      const desc = document.createElement('span');
      desc.className = 'slash-cmd-desc';
      desc.textContent = c.description || 'No description';
      desc.classList.toggle('is-empty', !c.description);
      // Long descriptions are cut to one line to keep every item the same height.
      if (c.description) li.title = c.description;
      const text = document.createElement('span');
      text.className = 'slash-cmd-text';
      text.append(name, desc);
      li.append(text);
      if (c.command) {
        const ignore = document.createElement('span');
        ignore.className = 'slash-cmd-ignore';
        ignore.textContent = 'I';
        ignore.title = `Ignore "/${c.command}"`;
        ignore.dataset.command = c.command;
        li.append(ignore);
      }
      m.appendChild(li);
    });
    // A long list scrolls; keep the highlighted item in view.
    m.querySelector('.is-selected')?.scrollIntoView({ block: 'nearest' });
    m.style.display = 'block';
    // We only show alongside GitHub's own menu, above it. Stay hidden until it opens; if it never
    // does, the "/" is not somewhere GitHub offers commands, so we close (see track).
    if (!s.revealed) {
      m.style.visibility = 'hidden';
      if (!sessionStart) sessionStart = performance.now();
      watchForGithub();
    }
    // Only one list may look focused: dim GitHub's highlight while ours has focus.
    document.documentElement.classList.toggle('slash-cmd-ours-focused', s.zone === 'ours');
    position();
    if (!tracking) {
      tracking = true;
      requestAnimationFrame(track);
    }
  }

  // GitHub's menu renders and shifts after our input handler, with no event to hook,
  // so follow it every frame while we are open.
  function track() {
    if (!isOpen()) {
      tracking = false;
      return;
    }
    position();
    if (!s.revealed) {
      if (githubModal()) reveal();
      else if (performance.now() - sessionStart >= REVEAL_TIMEOUT_MS) return close();
    }
    requestAnimationFrame(track);
  }

  function reveal() {
    s.revealed = true;
    stopWatchingForGithub();
    if (s.menu) s.menu.style.visibility = 'visible';
  }

  // The animation-frame loop only notices GitHub's menu a frame late, and later still if the page
  // is busy. A mutation observer runs before the browser paints, so we can show in the same frame.
  let githubWatcher = null;

  function watchForGithub() {
    if (githubWatcher) return;
    githubWatcher = new MutationObserver((records) => {
      // position() changes our own styles; reacting to that would loop.
      if (records.every((r) => s.menu && s.menu.contains(r.target))) return;
      if (!isOpen() || s.revealed) return stopWatchingForGithub();
      if (githubModal()) {
        position();
        reveal();
      }
    });
    githubWatcher.observe(document.body, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ['class', 'hidden', 'style'],
    });
  }

  function stopWatchingForGithub() {
    githubWatcher?.disconnect();
    githubWatcher = null;
  }

  // Where GitHub's menu will rest. It slides in over 120ms from 16px higher, and we line up with
  // the end of that slide so there is nothing to wait for.
  function githubRestingRect(modal) {
    const rect = modal.getBoundingClientRect();
    const slide = new DOMMatrixReadOnly(getComputedStyle(modal).transform).m42;
    return { left: rect.left, top: rect.top - slide };
  }

  // GitHub's built-in slash popup, if it is currently showing: either the list or, the first time
  // after a page load while GitHub fetches it, the loading box. Both rest in the same place, so
  // we can line up with the loading box and be there the moment GitHub's popup opens, without
  // waiting for the list to fill in.
  function githubModal() {
    // Only one slash menu can be open at a time, and the textarea is not always inside
    // its expander (the review-comment editor), so search the whole page. The expander
    // also holds hidden loading/error modals; take the one that is laid out.
    const selector = '.js-slash-command-menu .SelectMenu-modal, .js-slash-command-expander-loading .SelectMenu-modal';
    for (const modal of document.querySelectorAll(selector)) {
      if (modal.getBoundingClientRect().height > 0) return modal;
    }
    return null;
  }

  // Index of the item GitHub's menu currently highlights, -1 if none.
  function githubSelectedIndex(modal) {
    return [...modal.querySelectorAll('[role="option"]')].findIndex((o) => o.getAttribute('aria-selected') === 'true');
  }

  // Sit above GitHub's menu with a 2rem gap; otherwise follow the caret. Once anchored to
  // GitHub's menu, stay put if it closes (typing filters it away) rather than jumping.
  function position() {
    if (!isOpen() || !s.menu) return;
    const menu = s.menu;
    const target = s.target;
    const modal = githubModal();
    const gh = modal && githubRestingRect(modal);
    const taRect = target.getBoundingClientRect();
    let left, top;
    if (gh) {
      const gap = 2 * parseFloat(getComputedStyle(document.documentElement).fontSize);
      left = gh.left;
      top = gh.top - gap - menu.offsetHeight;
      // Kept relative to the textarea so it still follows the page when scrolled.
      anchor = { dx: left - taRect.left, dyBottom: top + menu.offsetHeight - taRect.top };
      if (!remembered) {
        remembered = true;
        const slash = caretRect(target, s.replaceFrom);
        memory.set(target, { dx: left - slash.left, dyBottom: top + menu.offsetHeight - slash.top });
      }
    } else if (anchor) {
      left = taRect.left + anchor.dx;
      top = taRect.top + anchor.dyBottom - menu.offsetHeight;
    } else if (memory.has(target)) {
      // GitHub's menu is not open here, but this is where it sat for a "/" in this textarea.
      const slash = caretRect(target, s.replaceFrom);
      const seen = memory.get(target);
      left = slash.left + seen.dx;
      top = slash.top + seen.dyBottom - menu.offsetHeight;
    } else {
      const caret = caretRect(target);
      left = caret.left;
      top = caret.top + caret.lineHeight + 4;
      if (top + menu.offsetHeight > window.innerHeight) top = caret.top - menu.offsetHeight - 4;
    }
    menu.style.left = Math.max(4, Math.min(left, window.innerWidth - menu.offsetWidth - 4)) + 'px';
    menu.style.top = Math.max(4, top) + 'px';
  }

  function close() {
    if (s.menu) s.menu.style.display = 'none';
    document.documentElement.classList.remove('slash-cmd-ours-focused');
    s.matches = [];
    s.target = null;
    s.zone = 'ours';
    anchor = null;
    s.revealed = false;
    sessionStart = 0;
    remembered = false;
    stopWatchingForGithub();
  }

  function isOpen() {
    return !!s.target && s.matches.length > 0;
  }

  ns.menu = { render, position, close, isOpen, reveal, githubModal, githubSelectedIndex };
})();
