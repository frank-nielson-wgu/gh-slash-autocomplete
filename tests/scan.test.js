// Regression tests for the page scanning in content/scan.js. Run with: node tests/scan.test.js
// Each case feeds in the text of one comment (and, optionally, commands already stored), runs the
// real scan.js against a stubbed page, and compares the commands it stored with what is expected.
// Every case is printed; a mismatch is logged with console.error() and the exit code becomes 1.
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'content', 'scan.js'), 'utf8');

// Runs scan.js on a page whose comments have these texts, and resolves to the commands in storage
// afterwards, as { name: [argument names] }.
async function scan(comments, stored = [], pathname = '/acme/site/issues/1') {
  let saved = JSON.parse(JSON.stringify(stored));
  const bodies = comments.map((text) => ({ textContent: text, firstElementChild: { textContent: text } }));
  const context = {
    window: { SlashCmd: { state: { commands: [], menu: null } } },
    location: { pathname },
    document: { querySelectorAll: () => bodies, body: {} },
    MutationObserver: class { observe() {} },
    chrome: {
      storage: {
        local: {
          get: async () => ({ commands: JSON.parse(JSON.stringify(saved)) }),
          set: async ({ commands }) => { saved = commands; },
        },
        onChanged: { addListener() {} },
      },
    },
    // The scan is debounced by a second; run it at once.
    setTimeout: (fn) => setTimeout(fn, 0),
    clearTimeout,
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  await new Promise((resolve) => setTimeout(resolve, 20));
  return Object.fromEntries(saved.map((c) => [c.name, c.args.map((a) => a.name)]));
}

const show = (commands) => Object.entries(commands).map(([name, args]) => `/${name} [${args.join(', ')}]`).join(' ') || '(nothing)';

// `comments` are the texts on the page, `expected` the commands that should be stored.
const cases = [
  // A comment that is a command and one word: the word is its argument.
  { comments: ['/q'], expected: { q: [] } },
  { comments: ['/q review'], expected: { q: ['review'] } },
  { comments: ['/q --full'], expected: { q: ['--full'] } },
  { comments: ['/q -h'], expected: { q: ['-h'] } },
  { comments: ['  /q review  '], expected: { q: ['review'] } },
  { comments: ['/Update-Baseline run'], expected: { 'Update-Baseline': ['run'] } },

  // The first word always counts; later words only when led with "-" or "--".
  { comments: ['/q update --full -h'], expected: { q: ['update', '--full', '-h'] } },
  { comments: ['/q --full -h'], expected: { q: ['--full', '-h'] } },
  { comments: ['/q update --full please'], expected: { q: ['update', '--full'] } },
  { comments: ['/q update today'], expected: { q: ['update'] } },
  { comments: ['/q the thing now'], expected: { q: ['the'] } },
  { comments: ['/q --full update'], expected: { q: ['--full'] } },

  // A word may carry a value.
  { comments: ['/q --limit=5'], expected: { q: ['--limit=5'] } },
  { comments: ['/q update --limit=5'], expected: { q: ['update', '--limit=5'] } },
  { comments: ['/q --limit=5 -h'], expected: { q: ['--limit=5', '-h'] } },
  { comments: ['/q --ratio=1.5'], expected: { q: ['--ratio=1.5'] } },
  { comments: ['/q update limit=5'], expected: { q: ['update'] } },
  { comments: ['/q --limit='], expected: { q: [] } },
  { comments: ['/q ='], expected: { q: [] } },

  // Prose after a command, or a command that is not at the start, gives no argument or nothing.
  { comments: ['/update-baseline please, thanks'], expected: { 'update-baseline': [] } },
  { comments: ['/q update, then --full'], expected: { q: [] } },
  { comments: ['run /q update --full'], expected: {} },
  { comments: ['no commands here'], expected: {} },
  { comments: [''], expected: {} },

  // GitHub's own slash menu entries are not bot commands.
  { comments: ['/table', '/details --open', '/saved-replies'], expected: {} },

  // Several comments, and repeats of an argument.
  { comments: ['/q review', '/q --full', '/deploy staging'], expected: { q: ['review', '--full'], deploy: ['staging'] } },
  { comments: ['/q review', '/q review', '/Q REVIEW'], expected: { q: ['review'] } },

  // An argument that is never scanned; its command and other arguments still are.
  { comments: ['/update-baseline --accept-violations'], expected: { 'update-baseline': [] } },
  { comments: ['/Update-Baseline --ACCEPT-VIOLATIONS'], expected: { 'Update-Baseline': [] } },
  { comments: ['/update-baseline --accept-violations=true'], expected: { 'update-baseline': [] } },
  { comments: ['/update-baseline review --accept-violations -h'], expected: { 'update-baseline': ['review', '-h'] } },
  { comments: ['/update-baseline --accept-violations-now'], expected: { 'update-baseline': ['--accept-violations-now'] } },
  { comments: ['/q --accept-violations'], expected: { q: ['--accept-violations'] } },

  // Commands that are already stored.
  { comments: ['/q --full'], stored: [{ name: 'q', enabled: true, source: 'manual', owners: [], args: [{ name: 'review' }] }], expected: { q: ['review', '--full'] } },
  { comments: ['/q --full'], stored: [{ name: 'q', enabled: true, source: 'manual', owners: [], autoArgs: false, args: [{ name: 'review' }] }], expected: { q: ['review'] } },
  { comments: ['/q --full'], stored: [{ name: 'q', enabled: true, source: 'manual', owners: [], args: [{ name: '--FULL' }] }], expected: { q: ['--FULL'] } },
];

(async () => {
  let failures = 0;
  for (const [i, { comments, stored, expected }] of cases.entries()) {
    const actual = await scan(comments, stored);
    const pass = JSON.stringify(actual) === JSON.stringify(expected);
    console.log(`${pass ? 'PASS' : 'FAIL'} #${i + 1}`);
    console.log(`  in:  ${comments.map((c) => JSON.stringify(c)).join(' ')}${stored ? `  (already stored: ${show(Object.fromEntries(stored.map((c) => [c.name, c.args.map((a) => a.name)])))})` : ''}`);
    console.log(`  out: ${show(actual)}`);
    if (!pass) {
      failures++;
      console.error(`  expected ${show(expected)} but got ${show(actual)}`);
    }
  }
  console.log(`\n${cases.length - failures} of ${cases.length} passed`);
  if (failures) {
    console.error(`${failures} failed`);
    process.exitCode = 1;
  }
})();
