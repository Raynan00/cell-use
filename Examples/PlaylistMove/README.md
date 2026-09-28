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
3. Enter a playlist name, new destination name, and one or five songs. Or tap **Say your request**, speak, then tap **Use recording**. Check the filled fields before starting. English speech is transcribed on device with SpeechAnalyzer; its language assets download on first use if needed.
4. Optionally paste the playlist's full Spotify link to open it directly. Tap **Move my playlist**. Once background work is ready, Spotify opens automatically. Leave the screen unlocked and in portrait. The app reads the playlist, navigates to Music, and works through the transfer.
5. Return to Playlist Move to inspect the result and export its timeline. Returning during a run stops further input. Use a new destination name for a fresh run.

Start with one song. If you stop a run, inspect the destination playlist before starting another.

## Recording

Use iPhone Screen Recording for the whole demo. Start before speaking your request. Check a short take to confirm microphone audio alongside voice input. Narration can be recorded afterward. Music playback is unnecessary.

The exported JSON includes model-decision timestamps, inference durations, transport acknowledgements and the final inventory. Decision timestamps describe when an action was chosen; the runner records when input was accepted. Use these to align captions with footage. Label sped-up sections and keep the original recording.

See [the demo script](demo-script.md) for the shot sequence and narration. Keep the first interaction at normal speed, then label sped-up sections while the remaining tracks move.

Inference and text recognition run on the phone. The music apps use their normal internet connections. Exporting a timeline is an explicit share action; it contains playlist and song names, but no screenshot files or pairing secrets.

Voice recordings are temporary files deleted after transcription or cancellation. Voice input only fills editable fields; it never starts a transfer. The microphone is released before Spotify opens.

## Development

```sh
swift test --package-path Examples/PlaylistMove
```

`PlaylistMoveCore` contains the inventory, verification rules and grounded actions. `LocalPlaylistAgent` implements `PhoneAgent`; another local model can replace it without changing the transport. The example uses text elements from Vision, rather than sending screenshots to a vision-language model.
