// The options page search. It uses the same fuzzy matching as the popup (matching.js), but also
// looks at descriptions, which the popup does not.

// The best score of `query` against any of `texts`, or null if none match.
function bestScore(query, texts) {
  let best = null;
  for (const text of texts) {
    const score = window.SlashCmd.matchScore(query, text);
    if (score !== null && (best === null || score > best)) best = score;
  }
  return best;
}

// Runs of spaces count as one, and people type the slash out of habit.
const normalizeQuery = (typed) => typed.replace(/^\s*\/+/, '').replace(/\s+/g, ' ').trim().toLowerCase();

// Whether `text` is something the search `typed` matches; false for an empty search. This is what
// the options page highlights.
function matchesSearch(typed, text) {
  const query = normalizeQuery(typed);
  return Boolean(query) && Boolean(text) && window.SlashCmd.matchScore(query, text) !== null;
}

// The commands that match `typed`, best first. A command matching by its name beats one matching
// by an argument, which beats one matching by a description (its own or an argument's); within
// each, the better fuzzy match comes first, then alphabetical. Everything matches an empty search.
function searchCommands(commands, typed) {
  const query = normalizeQuery(typed);
  if (!query) return commands;

  const tiers = (command) => [
    [command.name],
    command.args.map((a) => a.name),
    [command.description, ...command.args.map((a) => a.description)].filter(Boolean),
  ];

  return commands
    .map((command) => {
      const texts = tiers(command);
      for (let tier = 0; tier < texts.length; tier++) {
        const score = bestScore(query, texts[tier]);
        if (score !== null) return { command, tier, score };
      }
      return null;
    })
    .filter(Boolean)
    .sort((a, b) => a.tier - b.tier || b.score - a.score
      || a.command.name.localeCompare(b.command.name, undefined, { sensitivity: 'base' }))
    .map((entry) => entry.command);
}
