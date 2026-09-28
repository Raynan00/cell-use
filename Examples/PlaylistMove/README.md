# Playlist Move

Copy a small Spotify playlist into Apple Music using the apps on your iPhone. Built with cell-use, Apple's on-device Foundation Models, and Vision text recognition.

The model reads the current screen's text and chooses the next action. cell-use delivers taps, gestures, text and keyboard commands. The app keeps a song inventory and checks the destination playlist before reporting completion.

## Build

On macOS with Xcode 27 and the tools listed in the repository's setup guide:

```sh
bash Scripts/build-macos.sh PlaylistMove
```

The unsigned archive is `.build/playlist-move-unsigned.ipa`. The `Build Playlist Move` GitHub workflow produces the same archive. Sign it for your iPhone before installation.

## Run

1. Enable Apple Intelligence and finish its model download. Sign in to Spotify and Apple Music, with an active Apple Music subscription.
2. Enable Developer Mode and the local tunnel used by cell-use. Pair Playlist Move through the app's Connection setup section, then connect to this iPhone.
3. Open a small Spotify playlist in portrait. Return to Playlist Move and enter its exact name, a new destination name, and one or five songs.
4. Tap **Move my playlist**, wait for **Ready**, then switch back to Spotify. Leave the screen unlocked. The app reads the playlist, navigates to Music, and works through the transfer.
5. Return to Playlist Move to inspect the result and export its timeline. Returning during a run stops further input. Use a new destination name for a fresh run.

Start with one song. If you stop a run, inspect the destination playlist before starting another.

## Recording

Film the physical iPhone with a second camera. Show the start, then keep your hands away during the transfer. This also captures app transitions and the background-task indicator.

Try iOS Screen Recording for a clean second angle. Start recording before starting the transfer, and check a short run first. Some capture and mirroring combinations are restricted by iOS. Music playback is unnecessary.

The exported JSON includes model-decision timestamps, inference durations, transport acknowledgements and the final inventory. Decision timestamps describe when an action was chosen; the runner records when input was accepted. Use these to align captions with footage. Label sped-up sections and keep the original recording.

Suggested edit: show the Spotify playlist, start Playlist Move, show the app transition and first match, speed up the remaining work, then show the completed Apple Music playlist and play one track manually after the transfer has ended.

Inference and text recognition run on the phone. The music apps use their normal internet connections. Exporting a timeline is an explicit share action; it contains playlist and song names, but no screenshot files or pairing secrets.

## Development

```sh
swift test --package-path Examples/PlaylistMove
```

`PlaylistMoveCore` contains the inventory, verification rules and grounded actions. `LocalPlaylistAgent` implements `PhoneAgent`; another local model can replace it without changing the transport. The example uses text elements from Vision, rather than sending screenshots to a vision-language model.
