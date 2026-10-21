const NAME_PATTERN = /^[A-Za-z][\w-]*$/;
// An argument is what is typed after the command, e.g. "review" in "/q review". It can be
// several words, e.g. "review this", separated by single spaces. (Arguments the extension
// finds on pages are always one word, since it cannot tell where an argument would end and
// ordinary text begin.)
// A GitHub user or organization name, optionally followed by "/" and a repository name.
const OWNER_PATTERN = /^[a-z\d](?:[a-z\d-]*[a-z\d])?(?:\/[\w.-]+)?$/;
const ARGUMENT_PATTERN = /^[\w-]+(?: [\w-]+)*$/;

const list = document.getElementById('commands');
const empty = document.getElementById('empty');
const search = document.getElementById('search');
const noMatches = document.getElementById('no-matches');
const status = document.getElementById('status');

let commands = [];
let statusTimer = null;
const rows = new WeakMap(); // command -> its <li>
const argumentEditors = new WeakMap(); // command -> { addArgument(argument) }

// Create an element with the given properties and attributes, holding `children`.
function el(tag, props = {}, attrs = {}, ...children) {
  const node = Object.assign(document.createElement(tag), props);
  for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
  node.append(...children);
  return node;
}

// How long a row fades before it moves after being disabled (or enabled).
const SETTLE_MS = 1000;
const settleTimers = new WeakMap(); // command -> pending move

// Whether the row sorts among the disabled ones. That lags `enabled` by SETTLE_MS, so a row does
// not jump away the moment its checkbox is clicked.
const atBottom = (c) => (c.sortEnabled ?? c.enabled) === false;

// Disabled rows last; then alphabetical, ignoring case, with a row still being named last.
function byName(a, b) {
  if (atBottom(a) !== atBottom(b)) return atBottom(a) ? 1 : -1;
  if (Boolean(a.name) !== Boolean(b.name)) return a.name ? -1 : 1;
  return a.name.localeCompare(b.name, undefined, { sensitivity: 'base' });
}

// The commands as listed: by name, or, while searching, best match first with the rest after.
function displayOrder() {
  const found = searchCommands(commands, search.value);
  return found === commands ? commands : [...found, ...commands.filter((c) => !found.includes(c))];
}

// Show only the commands matching the search box, best match first.
function applySearch() {
  const found = new Set(searchCommands(commands, search.value));
  for (const command of commands) {
    const row = rows.get(command);
    row.hidden = !found.has(command);
    row.querySelector('.name').classList.toggle('match', matchesSearch(search.value, command.name));
    row.querySelector('.description').classList.toggle('match', matchesSearch(search.value, command.description));
    argumentEditors.get(command).highlight(search.value);
  }
  noMatches.hidden = found.size > 0 || commands.length === 0;
  sortRows();
}

// Reorder the rows in place so the one being edited keeps its place in the page.
function sortRows() {
  const focused = document.activeElement;
  commands.sort(byName);
  const sorted = displayOrder().map((c) => rows.get(c));
  // Rows already in order stay put, so a notice standing in for a removed row keeps its place.
  const shown = list.querySelectorAll(':scope > .command');
  if (sorted.length === shown.length && sorted.every((row, i) => row === shown[i])) return;
  list.append(...sorted);
  // Moving a row can drop focus; give it back.
  if (focused && focused !== document.body && document.activeElement !== focused) focused.focus();
}

// A name that has been saved, as opposed to one still being typed.
const isEstablished = (item) => Boolean(item.savedName) && item.savedName.toLowerCase() === item.name.toLowerCase();

// Whether `item` repeats a name in `list`. A saved name wins over a new one, so typing a
// duplicate flags only the new row and can never get the saved one dropped.
function collides(item, list) {
  return list.some((other) => other !== item
    && other.name.toLowerCase() === item.name.toLowerCase()
    && (isEstablished(other) || (!isEstablished(item) && list.indexOf(other) < list.indexOf(item))));
}

// Why a name can't be saved, or '' if it can.
function nameProblem(command) {
  if (!command.name) return 'Enter a command name.';
  if (!NAME_PATTERN.test(command.name)) return 'Use letters, numbers, "-" or "_", starting with a letter.';
  return collides(command, commands) ? 'Another command already uses this name.' : '';
}

// Why an argument can't be saved, or '' if it can.
function argumentProblem(command, argument) {
  if (!argument.name) return 'Enter an argument.';
  if (!ARGUMENT_PATTERN.test(argument.name)) return 'Use words of letters, numbers, "-" or "_", separated by spaces.';
  return collides(argument, command.args) ? 'This command already has that argument.' : '';
}

// "Acme, !@Beta, beta/site" -> ['acme', '!beta', 'beta/site']: lowercase, without "@", no
// repeats, invalid names dropped. A leading "!" excludes.
function parseOwners(text) {
  const owners = text.split(/[\s,]+/)
    .map((o) => o.replace(/^(!?)@/, '$1').toLowerCase())
    .filter((o) => OWNER_PATTERN.test(o.replace(/^!/, '')));
  return [...new Set(owners)];
}

function flash(message) {
  status.textContent = message;
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => { status.textContent = ''; }, 2000);
}

// Only valid commands and arguments are stored; a row being edited stays on screen until it is
// valid.
async function persist(message = 'Saved') {
  const valid = commands.filter((c) => !nameProblem(c));
  await chrome.storage.local.set({
    commands: valid.map((c) => ({
      name: c.name,
      description: c.description,
      enabled: c.enabled,
      source: c.source,
      owners: c.owners,
      args: c.args
        .filter((a) => !argumentProblem(c, a))
        .map(({ name, description }) => ({ name, description })),
    })),
  });
  flash(message);
}

function updateChrome() {
  empty.hidden = commands.length > 0;
}

// The row fades (see the CSS) now and moves to its place once the fade is done.
function setEnabled(command, enabled) {
  command.enabled = enabled;
  rows.get(command).querySelector('input[type="checkbox"]').checked = enabled;
  clearTimeout(settleTimers.get(command));
  settleTimers.set(command, setTimeout(() => {
    command.sortEnabled = enabled;
    sortRows();
  }, SETTLE_MS));
}

function refreshRow(row, command) {
  const problem = nameProblem(command);
  row.querySelector('.name').setAttribute('aria-invalid', String(Boolean(problem)));
  const meta = row.querySelector('.meta');
  meta.hidden = !problem;
  meta.textContent = problem;
}

// The collapsible list of a command's arguments, with a name and description for each.
function createArgumentsEditor(command) {
  command.args = (command.args ?? []).map((a) => ({ name: a.name, description: a.description ?? '' }));
  command.args.sort(byName);

  const summary = el('summary');
  const items = el('ul', { className: 'arg-list' });
  const add = el('button', { type: 'button', textContent: 'Add argument' });
  const details = el('details', { className: 'args' }, {}, summary, el('div', { className: 'args-body' }, {}, items, add));

  const refreshSummary = () => {
    summary.textContent = `Arguments (${command.args.length})`;
  };

  const fields = []; // { argument, name, description } for each argument row
  let openedBySearch = false;

  function addRow(argument) {
    // Last name that passed validation; '' for a new argument that has never had one.
    argument.savedName = argumentProblem(command, argument) ? '' : argument.name;

    const name = el('input', { type: 'text', className: 'arg-name', value: argument.name, placeholder: 'arg1 arg2...' }, { 'aria-label': 'Argument' });
    const description = el('input', { type: 'text', value: argument.description, placeholder: 'Description (optional)' }, { 'aria-label': 'Argument description' });
    const remove = el('button', { type: 'button', className: 'remove', textContent: 'Remove' });
    const item = el('li', { className: 'arg' }, {}, name, description, remove);

    const refresh = () => {
      const problem = argumentProblem(command, argument);
      name.setAttribute('aria-invalid', String(Boolean(problem)));
      name.title = problem;
    };

    // Runs of spaces are one space, and the ends are trimmed.
    name.addEventListener('input', () => { argument.name = name.value.replace(/\s+/g, ' ').trim(); refresh(); });
    name.addEventListener('change', () => {
      const problem = argumentProblem(command, argument);
      let message = 'Saved';
      if (problem && argument.savedName) {
        // Don't let a typo drop an argument that was already saved.
        argument.name = argument.savedName;
        message = `Argument not changed: ${problem}`;
      } else if (!problem) {
        argument.savedName = argument.name;
      }
      name.value = argument.name;
      refresh();
      persist(message);
    });
    description.addEventListener('input', () => { argument.description = description.value; });
    description.addEventListener('change', () => persist());
    fields.push({ argument, name, description });
    remove.addEventListener('click', () => {
      command.args = command.args.filter((a) => a !== argument);
      fields.splice(fields.findIndex((f) => f.argument === argument), 1);
      item.remove();
      refreshSummary();
      persist();
    });

    refresh();
    items.append(item);
    return item;
  }

  for (const argument of command.args) addRow(argument);
  refreshSummary();

  add.addEventListener('click', () => {
    const argument = { name: '', description: '' };
    command.args.push(argument);
    const item = addRow(argument);
    refreshSummary();
    item.querySelector('.arg-name').focus();
  });

  argumentEditors.set(command, {
    // Mark the argument fields the search matches, and open the list to show them. It closes
    // again once nothing in it matches, unless it was opened by hand.
    highlight(query) {
      let matched = false;
      for (const { argument, name, description } of fields) {
        const byName = matchesSearch(query, argument.name);
        const byDescription = matchesSearch(query, argument.description);
        name.classList.toggle('match', byName);
        description.classList.toggle('match', byDescription);
        matched ||= byName || byDescription;
      }
      if (matched && !details.open) {
        details.open = true;
        openedBySearch = true;
      } else if (!matched && openedBySearch) {
        details.open = false;
        openedBySearch = false;
      }
    },

    // An argument found on a page while this one is open.
    addArgument(argument) {
      const added = { name: argument.name, description: argument.description ?? '' };
      command.args.push(added);
      addRow(added);
      refreshSummary();
    },
  });

  return details;
}

function createRow(command) {
  command.owners ??= [];
  command.sortEnabled = command.enabled;
  // Last name that passed validation; '' for a new row that has never had one.
  command.savedName = nameProblem(command) ? '' : command.name;

  const enabled = el('input', { type: 'checkbox', checked: command.enabled, title: 'Is enabled?' }, { 'aria-label': 'Enabled' });
  const name = el('input', { type: 'text', className: 'name', value: command.name, placeholder: 'command' }, { 'aria-label': 'Command name' });
  const nameField = el('label', { className: 'name-field' }, {}, el('span', { textContent: '/' }, { 'aria-hidden': 'true' }), name);
  const description = el('input', { type: 'text', className: 'description', value: command.description, placeholder: 'Description (optional)' }, { 'aria-label': 'Description' });
  const remove = el('button', { type: 'button', className: 'remove', textContent: 'Remove' }, { 'aria-label': `Remove ${command.name || 'command'}` });
  const owners = el('input', { type: 'text', value: command.owners.join(', '), placeholder: 'All users and organizations or: wgu-edu, !wgu-edu (excluded), wgu-edu/student-portal, etc.' }, { 'aria-label': 'Applies to users, organizations and repositories' });
  const ownersField = el('label', { className: 'owners-field' }, {}, el('span', { textContent: 'Only for' }), owners);
  const meta = el('div', { className: 'meta' });
  const row = el('li', { className: 'command' }, {}, enabled, nameField, description, remove, ownersField, meta, createArgumentsEditor(command));

  enabled.addEventListener('change', () => {
    setEnabled(command, enabled.checked);
    persist();
  });
  name.addEventListener('input', () => {
    // People type the slash out of habit; it is shown separately.
    command.name = name.value.replace(/^\/+/, '').trim();
    refreshRow(row, command);
  });
  name.addEventListener('change', () => {
    const problem = nameProblem(command);
    let message = 'Saved';
    if (problem && command.savedName) {
      // Don't let a typo drop a command that was already saved.
      command.name = command.savedName;
      message = `Name not changed: ${problem}`;
    } else if (!problem) {
      // A command the user has renamed is theirs now, not one found on a page.
      if (command.source === 'scanned' && command.savedName && command.savedName !== command.name) {
        command.source = 'manual';
      }
      command.savedName = command.name;
    }
    name.value = command.name;
    refreshRow(row, command);
    remove.setAttribute('aria-label', `Remove ${command.name || 'command'}`);
    sortRows();
    persist(message);
  });
  description.addEventListener('input', () => { command.description = description.value; });
  description.addEventListener('change', () => persist());
  owners.addEventListener('change', () => {
    command.owners = parseOwners(owners.value);
    owners.value = command.owners.join(', ');
    persist();
  });
  remove.addEventListener('click', () => {
    const index = commands.indexOf(command);
    commands.splice(index, 1);
    persist();
    // The removal is saved at once; the notice in the row's place offers to take it back until the page is reloaded.
    const undo = el('button', { type: 'button', textContent: 'Undo' });
    const notice = el('li', { className: 'removed' }, {}, el('span', { textContent: `Removed /${command.name || 'command'}.` }), undo);
    // Undo is as wide as the Remove button it replaces, so it sits in the same place.
    undo.style.minWidth = `${remove.offsetWidth}px`;
    undo.addEventListener('click', () => {
      // A page may have added the same command again in the meantime.
      if (commands.some((c) => c.name.toLowerCase() === command.name.toLowerCase())) return notice.remove();
      commands.splice(index, 0, command);
      notice.replaceWith(row);
      updateChrome();
      persist('Restored');
    });
    row.replaceWith(notice);
    updateChrome();
  });

  refreshRow(row, command);
  rows.set(command, row);
  return row;
}

function render() {
  list.textContent = '';
  commands.sort(byName);
  for (const command of commands) list.append(createRow(command));
  updateChrome();
}

search.addEventListener('input', applySearch);

document.getElementById('add').addEventListener('click', () => {
  // A new, empty command would not match the search and so would be hidden.
  if (search.value) {
    search.value = '';
    applySearch();
  }
  const command = { name: '', description: '', enabled: true, source: 'manual', owners: [], args: [] };
  commands.push(command);
  const row = createRow(command);
  list.append(row);
  updateChrome();
  row.querySelector('.name').focus();
});

// Pages being browsed add commands while this page is open; show them without touching
// rows the user may be editing.
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== 'local' || !changes.commands) return;
  for (const stored of changes.commands.newValue ?? []) {
    const existing = commands.find((c) => c.name.toLowerCase() === stored.name.toLowerCase());
    if (!existing) {
      commands.push(stored);
      list.append(createRow(stored));
      continue;
    }
    // Ignored (disabled) from the popup while this page is open.
    if (stored.enabled !== existing.enabled) setEnabled(existing, stored.enabled);
    // A known command may have gained arguments.
    for (const argument of stored.args ?? []) {
      const known = existing.args.some((a) => a.name.toLowerCase() === argument.name.toLowerCase());
      if (!known) argumentEditors.get(existing)?.addArgument(argument);
    }
  }
  applySearch();
  updateChrome();
});

chrome.storage.local.get(['commands', 'ignored']).then(async (stored) => {
  commands = stored.commands ?? [];
  // Earlier versions kept a separate list of removed commands. Removing now just deletes.
  if (stored.ignored) await chrome.storage.local.remove('ignored');

  render();
});
