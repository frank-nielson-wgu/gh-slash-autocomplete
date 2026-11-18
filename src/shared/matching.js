(function () {
  'use strict';

  const ns = window.SlashCmd;

  // A slash command is only suggested when it is the first thing on a line, as with GitHub's own
  // slash menu; `before` is the text of the caret's line up to the caret.
  // Typing a command: "/up". Typing its argument, after a space: "/q rev". An argument may be
  // several words ("/q review this") when it was added by hand on the options page, so what
  // follows the command is any run of words; it only matters if it matches a known argument.
  const COMMAND_TRIGGER = /^\/([\w-]*)$/;
  // A word may carry a value, e.g. "--limit=5", and is still being typed after the "=".
  const ARGUMENT_TRIGGER = /^\/([\w-]+)[ \t]+((?:[\w-]+(?:=[\w.-]*)?(?:[ \t]+[\w-]+(?:=[\w.-]*)?)*[ \t]*)?)$/;

  // What to suggest for the text before the caret: commands, or, once a known command and a
  // space are typed, that command's arguments. Returns null when there is nothing to suggest.
  function suggestionsFor(before, commands) {
    const argumentMatch = ARGUMENT_TRIGGER.exec(before);
    if (argumentMatch) {
      const command = commands.find((c) => c.name.toLowerCase() === argumentMatch[1].toLowerCase());
      if (!command) return null;
      return argumentSuggestions(command, argumentMatch[2]);
    }

    const commandMatch = COMMAND_TRIGGER.exec(before);
    if (!commandMatch) return null;
    const query = commandMatch[1].toLowerCase();
    const found = rankByMatch(commands, query);
    if (!found.length) return null;

    // A fully typed command that no other command starts with: it is the one being used, so
    // offer it along with its arguments without waiting for the space. (Other commands that only
    // fuzzily match, say by containing the same letters, do not stop that.)
    const exact = commands.find((c) => c.name.toLowerCase() === query);
    const continues = (c) => c !== exact && c.name.toLowerCase().startsWith(query);
    if (query && exact && !commands.some(continues)) {
      return argumentSuggestions(exact, '');
    }

    return commandSuggestions(found);
  }

  // How well `query` matches `text`, higher being better, or null if it does not match. The
  // query matches when its letters appear in the text in order, though not necessarily together
  // ("rw" matches "review"). An exact match beats a prefix, which beats the query appearing
  // whole inside the text, which beats letters scattered through it; among scattered matches,
  // letters that run together, start a word, or sit close to the previous one score higher.
  function matchScore(query, text) {
    if (!query) return 0;
    const t = text.toLowerCase();
    if (t === query) return 10000;
    if (t.startsWith(query)) return 9000 - t.length;
    const at = t.indexOf(query);
    if (at >= 0) return 8000 - at * 10 - t.length;

    let score = 0;
    let from = 0;
    let last = -2;
    for (const ch of query) {
      const i = t.indexOf(ch, from);
      if (i < 0) return null;
      if (i === last + 1) score += 5;
      if (i === 0 || ' -_'.includes(t[i - 1])) score += 3;
      score -= i - from;
      last = i;
      from = i + 1;
    }
    // Between equally good matches, the shorter text is the closer one.
    return score - t.length * 0.1;
  }

  // The items whose name matches `query`, best match first (ties alphabetically).
  function rankByMatch(items, query) {
    return items
      .map((item) => ({ item, score: matchScore(query, item.name) }))
      .filter((entry) => entry.score !== null)
      .sort((a, b) => b.score - a.score || a.item.name.localeCompare(b.item.name, undefined, { sensitivity: 'base' }))
      .map((entry) => entry.item);
  }

  function commandSuggestions(found) {
    return {
      mode: 'commands',
      heading: 'Bot commands',
      start: 0, // the command starts the line, so everything is replaced from the line's beginning
      // Each command is followed by its arguments, so they can be picked without typing the whole
      // command first. The popup scrolls when this gets long.
      items: found.flatMap((c) => [
        {
          label: `/${c.name}`,
          description: c.description,
          command: c.name,
          // The space after a command is what starts its arguments.
          insert: `/${c.name} `,
          done: c.args.length === 0,
        },
        ...c.args.map((a) => {
          const text = `/${c.name} ${a.name}`;
          return { label: text, description: a.description, insert: text, done: true };
        }),
      ]),
    };
  }

  // What to offer once `command` is the one in use and `typed` is what follows it: the command
  // itself, then its arguments that match what was typed, best first. Items replace the text
  // from the command's slash.
  function argumentSuggestions(command, typed) {
    // Runs of spaces count as one, so "/q  review   th" still matches "review this".
    const query = typed.replace(/[ \t]+/g, ' ').toLowerCase();
    const args = rankByMatch(command.args, query);
    const argumentItems = args.map((a) => {
      const text = `/${command.name} ${a.name}`;
      return { label: text, description: a.description, insert: text, done: true };
    });

    // Nothing left to complete once the full argument has been typed, and nothing to suggest
    // when what was typed matches no argument.
    if (query && (!args.length || (args.length === 1 && args[0].name.toLowerCase() === query))) return null;

    // The command on its own stays a choice. It replaces any space already typed, so the space
    // is not doubled.
    const bare = { label: `/${command.name}`, description: command.description, command: command.name, insert: `/${command.name} `, done: true };
    return {
      mode: args.length ? 'arguments' : 'commands',
      heading: args.length ? `Arguments for /${command.name}` : 'Bot commands',
      start: 0,
      items: [bare, ...argumentItems],
      // With nothing typed the command comes first. Once an argument is being typed, the best
      // matching one is what Tab and Enter should take, not the bare command above it.
      defaultIndex: query ? 1 : 0,
    };
  }

  ns.suggestionsFor = suggestionsFor;
  ns.matchScore = matchScore;
})();
