(function () {
  'use strict';

  const s = window.SlashCmd.state;

  // --- Command list: storage and page scanning -------------------------------------------

  const SCAN_DEBOUNCE_MS = 1000;
  // `/name`, optionally followed by an argument, as the whole text of an inline code span,
  // e.g. "comment `/update-baseline` to ..." or "use `/q review`".
  const CODE_SPAN_COMMAND = /^\/([a-z][\w-]*)(?:[ \t]+(.+))?$/i;
  // An argument found on a page is a single word: we cannot tell where a longer one would end
  // and ordinary text begin. Anything else after a command (a placeholder such as "<env>", or
  // several words) is not taken. Several-word arguments can still be added by hand.
  const ARGUMENT_WORD = /^[\w-]+$/;
  // A comment that is nothing but a command and at most one word, e.g. "/q review": someone
  // running the command, so the word is its argument.
  const WHOLE_COMMENT_COMMAND = /^\/([a-z][\w-]*)(?:[ \t]+([\w-]+))?$/i;
  // A comment that merely opens with a command, e.g. "/update-baseline please, thanks". What
  // follows is ordinary prose there, so only the command is taken.
  const LEADING_COMMAND = /^\/([a-z][\w-]*)(?=\s|$)/i;
  // GitHub's own slash menu entries; these are not bot commands.
  const BUILT_IN = new Set([
    'alert', 'alerts', 'code', 'details', 'quote', 'replies', 'saved', 'saved-replies',
    'table', 'tasklist', 'template', 'templates',
  ]);

  const byName = (a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' });

  // The user or organization whose page this is, and its repository if it is one, from the path
  // (github.com/acme/repo, github.com/orgs/acme/...); '' where there is none.
  function pageOwner() {
    const [first, second] = location.pathname.split('/').filter(Boolean);
    return (first === 'orgs' ? second : first)?.toLowerCase() ?? '';
  }

  function pageRepo() {
    const [owner, repo] = location.pathname.split('/').filter(Boolean);
    return owner === 'orgs' ? '' : (repo?.toLowerCase() ?? '');
  }

  // Whether a command with these entries applies to `owner`/`repo`. An entry is an owner
  // ("acme") covering all its repositories, or one repository ("acme/site"); "!" excludes it.
  // The most specific entry that matches wins, so ["!acme", "acme/site"] is only acme/site. With
  // no entries a command applies everywhere, and with no match only when every entry excludes.
  function applies(entries, owner, repo) {
    if (!entries?.length) return true;
    const path = `${owner}/${repo}`;
    const matching = (o) => [owner, path].includes(o.replace(/^!/, ''));
    const best = entries.filter(matching).sort((a, b) => b.length - a.length)[0];
    return best ? !best.startsWith('!') : entries.every((o) => o.startsWith('!'));
  }

  // Checked per use, as GitHub changes page without reloading.
  window.SlashCmd.commandsHere = () => {
    const owner = pageOwner();
    const repo = pageRepo();
    return s.commands.filter((c) => applies(c.owners, owner, repo));
  };

  function loadCommands(stored) {
    s.commands = (stored || [])
      .filter((c) => c.enabled && c.name)
      .map((c) => ({ ...c, args: (c.args || []).filter((a) => a.name).sort(byName) }))
      .sort(byName);
  }

  // Slash commands that rendered comments on this page mention or open with, as a map from
  // command name to the set of one-word arguments seen after it.
  function scanForCommands(root = document) {
    const found = new Map();
    const note = (name, argument) => {
      if (BUILT_IN.has(name.toLowerCase())) return;
      if (!found.has(name)) found.set(name, new Set());
      if (argument) found.get(name).add(argument);
    };
    for (const body of root.querySelectorAll('.markdown-body')) {
      for (const code of body.querySelectorAll('code')) {
        if (code.closest('pre')) continue;
        const match = CODE_SPAN_COMMAND.exec(code.textContent.trim());
        if (match) note(match[1], ARGUMENT_WORD.test(match[2] ?? '') ? match[2] : null);
      }
      const whole = WHOLE_COMMENT_COMMAND.exec(body.textContent.trim());
      if (whole) {
        note(whole[1], whole[2] ?? null);
        continue;
      }
      const opening = (body.firstElementChild?.textContent ?? '').trimStart();
      const match = LEADING_COMMAND.exec(opening);
      if (match) note(match[1], null);
    }
    return found;
  }

  // Add commands, and arguments for them, that we have not seen to the stored list. A command
  // found on a page applies to that page's owner, and to each further owner it is found under.
  // One the user has set to apply everywhere, or added themselves, is left as it is.
  async function recordCommands(found, owner) {
    const { commands: stored = [] } = await chrome.storage.local.get('commands');
    const known = new Map(stored.map((c) => [c.name.toLowerCase(), c]));
    let changed = false;
    for (const [name, argumentNames] of found) {
      let command = known.get(name.toLowerCase());
      if (!command) {
        command = { name, description: '', enabled: true, source: 'scanned', owners: owner ? [owner] : [], args: [] };
        stored.push(command);
        known.set(name.toLowerCase(), command);
        changed = true;
      }
      command.args ??= [];
      if (command.source === 'scanned' && owner && command.owners?.length
        && !command.owners.some((o) => o.replace(/^!/, '').split('/')[0] === owner)) {
        command.owners.push(owner);
        changed = true;
      }
      for (const argument of argumentNames) {
        if (command.args.some((a) => a.name.toLowerCase() === argument.toLowerCase())) continue;
        command.args.push({ name: argument, description: '' });
        changed = true;
      }
    }
    if (changed) await chrome.storage.local.set({ commands: stored });
  }

  let scanTimer = null;
  function scheduleScan() {
    clearTimeout(scanTimer);
    scanTimer = setTimeout(() => {
      const found = scanForCommands();
      // The extension may have been reloaded under a still-open tab.
      if (found.size) recordCommands(found, pageOwner()).catch(() => {});
    }, SCAN_DEBOUNCE_MS);
  }

  try {
    chrome.storage.local.get('commands').then(({ commands: stored }) => loadCommands(stored));
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area === 'local' && changes.commands) loadCommands(changes.commands.newValue);
    });
  } catch {
    // Extension context invalidated (reloaded); a page refresh picks up the new one.
  }

  // GitHub swaps page content without reloading, so rescan when the page changes,
  // ignoring our own popup.
  new MutationObserver((mutations) => {
    if (mutations.some((m) => !s.menu || !s.menu.contains(m.target))) scheduleScan();
  }).observe(document.body, { childList: true, subtree: true });
  scheduleScan();
})();
