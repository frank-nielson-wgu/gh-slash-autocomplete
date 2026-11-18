// The content scripts load in manifest order into one isolated world (invisible to GitHub's own
// scripts). They share this namespace; each file adds what the later ones need.
window.SlashCmd = {
  state: {
    // Enabled commands from the options page (chrome.storage.local), kept live by scan.js.
    commands: [],

    menu: null,
    target: null,
    zone: 'ours', // which list has keyboard focus: 'ours' or 'github'
    // We only show alongside GitHub's own menu, above it. GitHub's menu appears a moment after ours
    // is ready, so stay hidden until it does, and appear once in our final spot rather than at the
    // caret and then jumping. If it does not open within a timeout, GitHub offers no commands here
    // and we close without ever showing. Once shown we stay while the user types on, even after
    // GitHub's menu has filtered away.
    revealed: false,

    matches: [], // { label, description, insert, done } for each item shown
    selected: 0,
    mode: 'commands', // 'commands', or 'arguments' once a full command and a space are typed
    heading: 'Bot commands',
    replaceFrom: 0, // where in the textarea the text we replace starts
  },
};
