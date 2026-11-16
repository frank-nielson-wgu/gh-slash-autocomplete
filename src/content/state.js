// The content scripts load in manifest order into one isolated world (invisible to GitHub's own
// scripts). They share this namespace; each file adds what the later ones need.
window.SlashCmd = {
  state: {
    // Enabled commands from the options page (chrome.storage.local), kept live by scan.js.
    commands: [],

    menu: null,
    target: null,
    zone: 'ours', // which list has keyboard focus: 'ours' or 'github'
    // GitHub's menu opens when "/" is typed as the first thing in the box, so ours waits for it only
    // while the text is just that "/". As soon as anything follows it we are using one of our own
    // commands, which GitHub's menu will not show for, and likewise when we reopen after closing.
    githubExpected: false,
    // GitHub's menu appears a moment after ours. Stay hidden until it does (or a timeout passes,
    // for inputs GitHub's menu never shows for), so we appear once, in our final spot, rather
    // than at the caret and then jumping.
    revealed: false,

    matches: [], // { label, description, insert, done } for each item shown
    selected: 0,
    mode: 'commands', // 'commands', or 'arguments' once a full command and a space are typed
    heading: 'Bot commands',
    replaceFrom: 0, // where in the textarea the text we replace starts
  },
};
