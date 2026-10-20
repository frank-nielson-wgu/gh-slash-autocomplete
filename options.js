const NAME_PATTERN = /^[A-Za-z][\w-]*$/;
// An argument is what is typed after the command, e.g. "review" in "/q review". It can be
// several words, e.g. "review this", separated by single spaces. (Arguments the extension
// finds on pages are always one word, since it cannot tell where an argument would end and
// ordinary text begin.)
const ARGUMENT_PATTERN = /^[\w-]+(?: [\w-]+)*$/;

const list = document.getElementById('commands');
const empty = document.getElementById('empty');
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

// Alphabetical, ignoring case; a row still being named goes last.
function byName(a, b) {
  if (Boolean(a.name) !== Boolean(b.name)) return a.name ? -1 : 1;
  return a.name.localeCompare(b.name, undefined, { sensitivity: 'base' });
}

// Reorder the rows in place so the one being edited keeps its place in the page.
function sortRows() {
  const focused = document.activeElement;
  commands.sort(byName);
  for (const command of commands) list.append(rows.get(command));
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

function refreshRow(row, command) {
  const problem = nameProblem(command);
  row.querySelector('.name').setAttribute('aria-invalid', String(Boolean(problem)));
  const meta = row.querySelector('.meta');
  if (problem) {
    meta.dataset.error = '';
    meta.textContent = problem;
  } else {
    delete meta.dataset.error;
    meta.textContent = command.source === 'scanned' ? 'Found on a GitHub page' : 'Added by you';
  }
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

  function addRow(argument) {
    // Last name that passed validation; '' for a new argument that has never had one.
    argument.savedName = argumentProblem(command, argument) ? '' : argument.name;

    const name = el('input', { type: 'text', className: 'arg-name', value: argument.name, placeholder: 'argument' }, { 'aria-label': 'Argument' });
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
    remove.addEventListener('click', () => {
      command.args = command.args.filter((a) => a !== argument);
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
  // Last name that passed validation; '' for a new row that has never had one.
  command.savedName = nameProblem(command) ? '' : command.name;

  const enabled = el('input', { type: 'checkbox', checked: command.enabled }, { 'aria-label': 'Enabled' });
  const name = el('input', { type: 'text', className: 'name', value: command.name, placeholder: 'command' }, { 'aria-label': 'Command name' });
  const nameField = el('label', { className: 'name-field' }, {}, el('span', { textContent: '/' }, { 'aria-hidden': 'true' }), name);
  const description = el('input', { type: 'text', className: 'description', value: command.description, placeholder: 'Description (optional)' }, { 'aria-label': 'Description' });
  const remove = el('button', { type: 'button', className: 'remove', textContent: 'Remove' }, { 'aria-label': `Remove ${command.name || 'command'}` });
  const meta = el('div', { className: 'meta' });
  const row = el('li', { className: 'command' }, {}, enabled, nameField, description, remove, meta, createArgumentsEditor(command));

  enabled.addEventListener('change', () => {
    command.enabled = enabled.checked;
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
  remove.addEventListener('click', () => {
    commands = commands.filter((c) => c !== command);
    row.remove();
    updateChrome();
    persist();
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

document.getElementById('add').addEventListener('click', () => {
  const command = { name: '', description: '', enabled: true, source: 'manual', args: [] };
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
    // A known command may have gained arguments.
    for (const argument of stored.args ?? []) {
      const known = existing.args.some((a) => a.name.toLowerCase() === argument.name.toLowerCase());
      if (!known) argumentEditors.get(existing)?.addArgument(argument);
    }
  }
  sortRows();
  updateChrome();
});

chrome.storage.local.get(['commands', 'ignored']).then(async (stored) => {
  // Earlier versions kept a list of removed commands, and briefly flagged rows as ignored.
  // Removing now just deletes, so drop both.
  const flagged = (stored.commands ?? []).filter((c) => c.ignored);
  commands = (stored.commands ?? []).filter((c) => !c.ignored);
  if (stored.ignored || flagged.length) {
    await chrome.storage.local.remove('ignored');
    if (flagged.length) await persist('Saved');
  }

  render();
});
