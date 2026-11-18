# Chrome Web Store listing

Copy-paste text for the Developer Dashboard. Not part of the extension zip.

## Store listing tab

**Name:** GitHub bot slash-command autocomplete

**Summary** (from the manifest `description`; 132 characters max, currently 121):
Autocomplete for bot slash commands in GitHub comment boxes. Learns commands from the pages you visit. No network access.

**Category:** Developer Tools

**Language:** English

**Description:**

Type `/` in a GitHub comment box and get a menu of the bot slash commands your team uses, such as `/q review` or `/retest`, with the arguments each one accepts.

The extension learns commands as you browse. When a rendered comment on a GitHub page starts with a slash command, the command and its one-word arguments are added to your list. You can also add them by hand.

FEATURES
- Suggestions in any GitHub comment box, filtered as you type
- Learns commands and arguments from the pages you visit
- Options page to edit, disable, remove or add commands and arguments
- Limit a command to the users, organizations or repositories it applies to (for example `acme, octocat, acme/site`), and exclude one with `!`
- Ignore a command from the menu with one click; bring it back from the options page
- Export your commands to a JSON file and import them on another machine or share them with your team

PRIVATE BY DESIGN
- Runs only on github.com
- Only permission: storage (your list stays on your device)
- Makes no network requests, loads no remote code, has no analytics or tracking
- Keeps only command names, their arguments and the owner they were found under; never comment text

Open source (MIT): https://github.com/frank-nielson-wgu/gh-slash-autocomplete

GitHub is a trademark of GitHub, Inc. This extension is not affiliated with or endorsed by GitHub.

## Graphics tab

- **Icon (128x128):** `src/icons/icon-128.png` (already in the zip)
- **Screenshots (1280x800 or 640x400, at least 1, up to 5):** TODO. Suggested: (1) the menu open in a PR comment box, (2) the options page with a few commands, (3) a command's arguments and *Only for* scoping.
- **Small promo tile (440x280):** TODO (required by the dashboard).
- Marquee promo tile (1400x560): optional.

## Privacy tab

**Single purpose:**
Suggest bot slash commands, and their arguments, in GitHub comment boxes.

**Permission justification: `storage`:**
Saves the user's list of slash commands, their arguments, and the user's settings on the device so the menu and options page can use them. Nothing is synced or sent anywhere.

**Host permission justification: `https://github.com/*` (content script):**
The content script shows the suggestion menu in GitHub comment boxes and reads rendered comments on the page to find slash commands to suggest. It runs on no other site.

**Remote code:** No, I am not using remote code.

**Data usage** (what the extension collects):
Tick **none** of the data types. The extension reads page text locally only to find command names, and does not collect or transmit user data. If the dashboard's definitions make you hesitate over "Website content", the honest answer is still that nothing is collected: collecting means transmitting off the device, and nothing leaves it.

Then tick all three certifications:
- I do not sell or transfer user data to third parties, outside of the approved use cases
- I do not use or transfer user data for purposes unrelated to the item's single purpose
- I do not use or transfer user data to determine creditworthiness or for lending purposes

**Privacy policy URL:**
https://github.com/frank-nielson-wgu/gh-slash-autocomplete/blob/main/PRIVACY.md
(Works only once `PRIVACY.md` is merged to `main`.)

## Distribution tab

- **Visibility:** Unlisted (anyone with the link can install; not searchable)
- **Regions:** all
- **Pricing:** free

## Test instructions (optional but speeds review)

No account or credentials needed. Open any GitHub pull request page that has a comment starting with a slash command (for example `/retest`); the command is picked up after about a second and listed on the options page (click the toolbar icon). Then type `/` in a comment box on github.com to see the menu. To try it without a bot, add a command by hand on the options page.
