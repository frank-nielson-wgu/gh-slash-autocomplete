const NAME_PATTERN = /^[A-Za-z][\w-]*$/;
// An argument is what is typed after the command, e.g. "review" in "/q review". It can be
// several words, e.g. "review this", separated by single spaces. (Arguments the extension
// finds on pages are always one word, since it cannot tell where an argument would end and
// ordinary text begin.)
// A GitHub user or organization name, optionally followed by "/" and a repository name.
const OWNER_PATTERN = /^[a-z\d](?:[a-z\d-]*[a-z\d])?(?:\/[\w.-]+)?$/;
const ARGUMENT_PATTERN = /^[\w-]+(?: [\w-]+)*$/;

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
