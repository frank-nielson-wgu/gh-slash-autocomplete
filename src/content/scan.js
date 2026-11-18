(function () {
  'use strict';

  const s = window.SlashCmd.state;

  // --- Command list: storage and page scanning -------------------------------------------

  const SCAN_DEBOUNCE_MS = 1000;
  // Only a comment that starts with the "/" counts; a command mentioned mid-text, even in an inline
  // code span, is not taken. An argument found on a page is a single word: we cannot tell where a
  // longer one would end and ordinary text begin. Several-word arguments can still be added by hand.
  // A comment that is nothing but a command and words, e.g. "/q review --full -h": someone
  // running the command. The first word is an argument, and so is any later one led with "-" or
  // "--"; a later bare word could just be text being typed, so "/q review today" gives only "review".
  // A word may carry a value, e.g. "--limit=5".
  const WHOLE_COMMENT_COMMAND = /^\/([a-z][\w-]*)((?:[ \t]+[\w-]+(?:=[\w.-]+)?)*)$/i;
  // A comment that merely opens with a command, e.g. "/update-baseline please, thanks". What
  // follows is ordinary prose there, so only the command is taken.
  const LEADING_COMMAND = /^\/([a-z][\w-]*)(?=\s|$)/i;
  // GitHub's own slash menu entries; these are not bot commands.
  const BUILT_IN = new Set([
    'alert', 'alerts', 'code', 'details', 'quote', 'replies', 'saved', 'saved-replies',
    'table', 'tasklist', 'template', 'templates',
  ]);

  // Commands with an argument that is never taken from a page, as "command argument". The command
  // itself is still found; only that argument is left out, with or without a "=value".
  const NEVER_SCANNED = new Set(['update-baseline --accept-violations']);

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

  // Stop suggesting a command, at once and in storage, by disabling it. The options page lists
  // disabled commands last, where its checkbox brings the command back.
  window.SlashCmd.ignoreCommand = async (name) => {
    const same = (c) => c.name.toLowerCase() === name.toLowerCase();
    s.commands = s.commands.filter((c) => !same(c));
    const { commands: stored = [] } = await chrome.storage.local.get('commands');
    const command = stored.find(same);
    if (!command) return;
    command.enabled = false;
    await chrome.storage.local.set({ commands: stored });
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
    const note = (name, args = []) => {
      if (BUILT_IN.has(name.toLowerCase())) return;
      if (!found.has(name)) found.set(name, new Set());
      for (const argument of args) {
        if (NEVER_SCANNED.has(`${name} ${argument.split('=')[0]}`.toLowerCase())) continue;
        found.get(name).add(argument);
      }
    };
    for (const body of root.querySelectorAll('.markdown-body')) {
      const whole = WHOLE_COMMENT_COMMAND.exec(body.textContent.trim());
      if (whole) {
        const words = whole[2].split(/[ \t]+/).filter(Boolean);
        note(whole[1], words.filter((w, i) => i === 0 || w.startsWith('-')));
        continue;
      }
      const opening = (body.firstElementChild?.textContent ?? '').trimStart();
      const match = LEADING_COMMAND.exec(opening);
      if (match) note(match[1]);
    }
    return found;
  }

  // What a command found on this page is scoped to: its repository ("acme/site"), or the owner
  // ("acme") on a page with no repository, such as an organization page.
  function pageScope() {
    const owner = pageOwner();
    const repo = pageRepo();
    return owner && repo ? `${owner}/${repo}` : owner;
  }

  // Add commands, and arguments for them, that we have not seen to the stored list. A command
  // found on a page applies to that page's repository (or owner, where the page has no
  // repository), and to each further repository it is found under. One the user has set to apply
  // everywhere, or added themselves, is left as it is.
  async function recordCommands(found, scope) {
    const owner = scope.split('/')[0];
    const { commands: stored = [] } = await chrome.storage.local.get('commands');
    const known = new Map(stored.map((c) => [c.name.toLowerCase(), c]));
    let changed = false;
    for (const [name, argumentNames] of found) {
      let command = known.get(name.toLowerCase());
      if (!command) {
        command = { name, description: '', enabled: true, source: 'scanned', owners: scope ? [scope] : [], args: [] };
        stored.push(command);
        known.set(name.toLowerCase(), command);
        changed = true;
      }
      command.args ??= [];
      if (command.source === 'scanned' && scope && command.owners?.length
        && !command.owners.some((o) => [scope, owner].includes(o.replace(/^!/, '')))) {
        command.owners.push(scope);
        changed = true;
      }
      // A command whose arguments the user has locked keeps exactly the ones it has.
      if (command.autoArgs === false) continue;
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
      if (found.size) recordCommands(found, pageScope()).catch(() => {});
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
