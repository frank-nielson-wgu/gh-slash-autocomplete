(function () {
  'use strict';

  const ns = window.SlashCmd;
  const s = ns.state;
  const { render, position, close, isOpen, reveal, githubModal, githubSelectedIndex } = ns.menu;

  // `openedGithub` is whether this update came from typing the "/" that opens GitHub's own menu.
  function update(ta, openedGithub = false) {
    if (ta.selectionStart !== ta.selectionEnd) return close();
    const before = ta.value.slice(0, ta.selectionStart);
    const suggestions = ns.suggestionsFor(before, s.commands);
    if (!suggestions) return close();
    // Only a lone "/" is worth waiting on GitHub's menu for. Typing on from it ends the wait.
    if (before !== '/') s.githubExpected = false;
    else if (!isOpen()) s.githubExpected = openedGithub;
    // Typing re-filters both menus and resets GitHub's highlight, so start from ours again. The
    // results are ranked afresh too, so the highlight goes back to the best match.
    s.zone = 'ours';
    s.target = ta;
    s.mode = suggestions.mode;
    s.heading = suggestions.heading;
    s.replaceFrom = suggestions.start;
    s.matches = suggestions.items;
    s.selected = Math.min(suggestions.defaultIndex ?? 0, s.matches.length - 1);
    render();
  }

  function accept(index) {
    const ta = s.target;
    const item = s.matches[index];
    if (!ta || !item) return close();
    const end = ta.selectionStart;
    const from = s.replaceFrom;
    ta.focus();
    ta.setSelectionRange(from, end);
    // execCommand keeps undo history and fires the events React listens for.
    if (!document.execCommand('insertText', false, item.insert)) {
      const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
      setter.call(ta, ta.value.slice(0, from) + item.insert + ta.value.slice(end));
      ta.setSelectionRange(from + item.insert.length, from + item.insert.length);
      ta.dispatchEvent(new Event('input', { bubbles: true }));
    }
    // A command that takes arguments moves us on to them. Anything else is complete: without this
    // we would reopen on the text just inserted.
    if (item.done) close();
    else update(ta);
  }

  // The popup's mouse handler (menu.js) selects through this.
  ns.accept = accept;

  document.addEventListener('input', (e) => {
    if (!(e.target instanceof HTMLTextAreaElement)) return;
    // GitHub's menu opens when "/" is typed as the first character of the box.
    const typedFirstSlash = e.data === '/' && e.target.value.slice(0, e.target.selectionStart) === '/';
    update(e.target, typedFirstSlash);
  }, true);

  document.addEventListener('keydown', (e) => {
    if (!isOpen() || e.target !== s.target || e.isComposing) return;
    // Shift+Enter is a new line, Ctrl+Enter submits the comment, Shift+Tab moves focus back, and
    // Shift+arrows extends the selection. None of those are ours to take.
    if (e.shiftKey || e.ctrlKey || e.metaKey || e.altKey) return;
    const swallow = () => { e.preventDefault(); e.stopImmediatePropagation(); };
    const modal = githubModal();
    // The user is already acting on the list, so don't keep it waiting.
    if (!s.revealed && ['ArrowDown', 'ArrowUp', 'Enter', 'Tab'].includes(e.key)) reveal();

    // GitHub's menu has focus: it handles its own keys, except moving up past its first item.
    if (s.zone === 'github') {
      if (e.key === 'ArrowUp' && (!modal || githubSelectedIndex(modal) <= 0)) {
        swallow(); s.zone = 'ours'; s.selected = s.matches.length - 1; render();
      } else if (e.key === 'Escape') {
        close();
      }
      return;
    }

    switch (e.key) {
      case 'ArrowDown':
        swallow();
        if (modal && s.selected === s.matches.length - 1) s.zone = 'github';
        else s.selected = (s.selected + 1) % s.matches.length;
        render();
        break;
      case 'ArrowUp':
        swallow();
        // Wrap only when there is no other list to go to.
        if (s.selected > 0) s.selected--;
        else if (!modal) s.selected = s.matches.length - 1;
        render();
        break;
      case 'Enter':
      case 'Tab':
        swallow(); accept(s.selected); break;
      case 'Escape':
        // With GitHub's menu open, let Esc through so it closes that menu too.
        // Without it, swallow Esc so it cannot cancel the surrounding comment form.
        if (!modal) swallow();
        close();
        break;
    }
  }, true);

  // Caret moved without typing (click, arrow keys) or focus left.
  document.addEventListener('click', (e) => {
    if (e.target instanceof HTMLTextAreaElement) update(e.target); else close();
  }, true);
  document.addEventListener('focusout', (e) => {
    if (e.target === s.target) close();
  }, true);
  // GitHub scrolls the page to fit its own menu, so follow it rather than close.
  window.addEventListener('scroll', position, true);
  window.addEventListener('resize', position);
})();
