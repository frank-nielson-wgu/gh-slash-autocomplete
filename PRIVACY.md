# Privacy policy

**GitHub bot slash-command autocomplete** does not collect, transmit, sell or share any data. Everything
it works with stays in your browser.

## What the extension reads

On `https://github.com/*` pages it reads the text of rendered comments (`.markdown-body` elements) to
find bot slash commands, such as `/q review`. It also reads the owner and repository name from the page
address (for example `acme` and `acme/site` from `github.com/acme/site`).

It looks only for comments that start with a `/` command. It keeps the command name, any one-word
arguments that follow it, and the repository (or owner) it was found under. It does not keep the comment text, author
names, issue or pull request content, or anything else on the page.

The extension does not read GitHub pages for any other purpose, and it does not run on any other site.

## What the extension stores

The commands above, plus what you enter on the options page (descriptions, arguments, enabled or
disabled state, and the users, organizations or repositories a command applies to), are saved in
`chrome.storage.local` on your device. Because owners come from page addresses, they can include the
names of private organizations or repositories you visit; they stay on your device like everything else.

The extension does not use `chrome.storage.sync`, so Chrome does not copy this data to your Google
account or other devices.

## What leaves your device

Nothing. The extension makes no network requests, loads no remote code, and has no analytics, telemetry,
advertising or error reporting. Its only permission is `storage`.

The one exception is under your control: **Export** on the options page saves your commands to a JSON
file on your computer. If you share that file, its contents are shared.

## Your control

Edit or remove any command on the options page, or remove the extension to delete all of its stored data.

## Changes

If this policy changes, the new version will be published in this repository, and the date below updated.

Last updated: 2026-11-18

## Contact

Questions or concerns: open an issue at <https://github.com/frank-nielson-wgu/gh-slash-autocomplete/issues>.
