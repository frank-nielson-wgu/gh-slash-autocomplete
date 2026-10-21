# GitHub slash-command autocomplete

A Chrome extension (Manifest V3) that autocompletes bot slash commands in GitHub comment boxes.
Type `/` in a comment and it suggests commands. It finds commands that bots mention in comments on
the pages you visit, and you can edit, disable, remove or add commands on the options page.

It runs only on `https://github.com/*`, needs only the `storage` permission, and makes no network
requests.

## Install from source

1. Open `chrome://extensions` and turn on **Developer mode**.
2. Click **Load unpacked** and choose this folder.

There is no build step. After editing a file, click the reload icon on the extension's card.

## Use

- Type `/` in a GitHub comment box to see suggestions. After a command and a space, the popup
  suggests that command's arguments. Click the **I** at the right of a command to ignore it: it is
  disabled, so it is no longer suggested, and moves to the bottom of the options page, where its
  checkbox brings it back.
- **Export** on the options page saves your commands and their arguments to a JSON file you can
  share; **Import** reads one back. Imported commands are added to yours; a command you already
  have keeps its settings and only gains the arguments it lacked.
- Open the extension's options page to manage commands. Under *Arguments*, list what a command
  accepts after it, such as `review` for `/q review`. Under *Only for*, list the GitHub users,
  organizations or repositories a command applies to (for example `acme, octocat, acme/site`); it
  is suggested only on their pages. An owner covers all its repositories; put `!` in front to
  exclude one, and the most specific entry wins, so `!acme, acme/site` means only `acme/site`. Leave it empty to suggest the command everywhere. Commands the extension finds are
  scoped to the owner of the page they were found on, and gain each further owner they turn up under.

## Files

| File | Purpose |
| --- | --- |
| `manifest.json` | Extension manifest |
| `content.js`, `content.css` | Content script entry point and menu styles |
| `state.js`, `matching.js`, `scan.js`, `menu.js` | Shared state, matching, page scanning, and the popup menu |
| `options.html`, `options.css`, `options.js` | Options page |
| `validation.js` | Options page: name, argument and owner checks |
| `share.js` | Options page: export and import |
| `icons/` | Toolbar and store icons |
| `pack.ps1` | Builds the Web Store zip |

## Pack

```powershell
./pack.ps1
```

This writes `dist/gh-slash-autocomplete-<version>.zip`, containing only the files the extension
needs. Bump `version` in `manifest.json` before each upload, then upload the zip in the
[Chrome Developer Dashboard](https://chrome.google.com/webstore/devconsole).

## License

MIT. See [LICENSE](LICENSE).
