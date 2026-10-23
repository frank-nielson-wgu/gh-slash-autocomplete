const EXPORT_FORMAT = 'gh-slash-autocomplete';

// Download the saved commands as a JSON file that can be shared and imported elsewhere.
document.getElementById('export').addEventListener('click', () => {
  const valid = commands.filter((c) => !nameProblem(c));
  const data = {
    format: EXPORT_FORMAT,
    version: 1,
    commands: valid.map((c) => ({
      name: c.name,
      description: c.description,
      enabled: c.enabled,
      owners: c.owners,
      autoArgs: c.autoArgs,
      args: c.args
        .filter((a) => !argumentProblem(c, a))
        .map(({ name, description }) => ({ name, description })),
    })),
  };
  const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }));
  const link = el('a', { href: url, download: 'slash-commands.json' });
  link.click();
  URL.revokeObjectURL(url);
  flash(`Exported ${data.commands.length} command${data.commands.length === 1 ? '' : 's'}`);
});

// A command read from an import file, or null if it is not usable. Nothing is trusted: names
// and arguments must pass the same checks as ones typed in.
function sanitizeImported(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const name = typeof raw.name === 'string' ? raw.name.replace(/^\/+/, '').trim() : '';
  if (!NAME_PATTERN.test(name)) return null;
  const text = (value) => (typeof value === 'string' ? value : '');
  const args = [];
  for (const a of Array.isArray(raw.args) ? raw.args : []) {
    const argument = { name: text(a?.name).replace(/\s+/g, ' ').trim(), description: text(a?.description) };
    if (ARGUMENT_PATTERN.test(argument.name) && !collides(argument, [...args, argument])) args.push(argument);
  }
  return {
    name,
    description: text(raw.description),
    enabled: raw.enabled !== false,
    source: 'manual',
    autoArgs: raw.autoArgs !== false,
    owners: parseOwners(Array.isArray(raw.owners) ? raw.owners.filter((o) => typeof o === 'string').join(' ') : ''),
    args,
  };
}

// Add imported commands to the existing ones. A command that already exists keeps its own
// settings and only gains the arguments (and description) it lacked.
function mergeImported(imported) {
  let added = 0;
  let updated = 0;
  for (const incoming of imported) {
    const existing = commands.find((c) => c.name.toLowerCase() === incoming.name.toLowerCase());
    if (!existing) {
      commands.push(incoming);
      added++;
      continue;
    }
    let changed = false;
    if (!existing.description && incoming.description) {
      existing.description = incoming.description;
      changed = true;
    }
    for (const argument of incoming.args) {
      if (existing.args.some((a) => a.name.toLowerCase() === argument.name.toLowerCase())) continue;
      existing.args.push(argument);
      changed = true;
    }
    if (changed) updated++;
  }
  return { added, updated };
}

const importFile = document.getElementById('import-file');
document.getElementById('import').addEventListener('click', () => importFile.click());
importFile.addEventListener('change', async () => {
  const [file] = importFile.files;
  importFile.value = '';
  if (!file) return;
  let data;
  try {
    data = JSON.parse(await file.text());
  } catch {
    return flash('Import failed: not a valid JSON file');
  }
  if (data?.format !== EXPORT_FORMAT || !Array.isArray(data.commands)) {
    return flash('Import failed: not a slash commands export');
  }
  const { added, updated } = mergeImported(data.commands.map(sanitizeImported).filter(Boolean));
  render();
  applySearch();
  await persist(`Imported: ${added} added, ${updated} updated`);
});
