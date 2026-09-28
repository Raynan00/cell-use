# Playlist Move

Turn song recommendations from a screenshot into a Spotify playlist, or copy a small Spotify playlist into Apple Music. Built with cell-use, Apple's on-device Foundation Models, and Vision text recognition.

The model reads the current screen's text and chooses the next action. cell-use delivers taps, gestures, text and keyboard commands. The app keeps a song inventory; the agent inspects the destination and reports when it considers the task complete.

## Build

On macOS with Xcode 27 and the tools listed in the repository's setup guide:

```sh
bash Scripts/build-macos.sh PlaylistMove
```

The unsigned archive is `.build/playlist-move-unsigned.ipa`. The `Build Playlist Move` GitHub workflow produces the same archive. Sign it for your iPhone before installation.

If Sideloadly changes the app's bundle identifier, configure the background task identifier for that final signed ID before signing the archive again. Save the installed app's bundle ID in a local text file, then run:

```sh
python3 Scripts/configure-background-identifier.py --input .build/playlist-move-unsigned.ipa --output .build/playlist-move-configured.ipa --bundle-id-file .build/installed-playlist-bundle.txt
```

Sign the configured IPA with the same account and bundle settings. The helper preserves the executable and original bundle ID, and updates the background task entries. Keep the bundle ID file and configured IPA local.

## Screenshot to Spotify

1. Sign in to Spotify, enable Apple Intelligence and finish its model download. Keep Developer Mode and the local tunnel enabled. Pair and connect Playlist Move through Connection setup.
2. Tap **Choose screenshot**. The image appears at full card width while the local model reads its recommendations. The preview stays expanded above the extracted songs. Titles without artists are accepted and labeled **Find artist in Spotify**.
3. Check the songs and enter a new Spotify playlist name. Tap **Create playlist**. Spotify opens automatically, and the agent searches for the songs and adds them through its interface.
4. Keep the iPhone unlocked and in portrait. Return after the run to inspect the result and export its timeline.

For the demo, use a screenshot with three readable song recommendations. The agent can correct OCR mistakes, search by title, use Spotify's suggestions and infer the intended recording from the recommendations and results. It chooses its navigation and recovery steps. Hold on the preview long enough to read it, show the extracted songs, then film the automatic Spotify actions with your hands away.

## Optional: hands-free from Photos

1. Sign in to Spotify, enable Apple Intelligence and finish its model download. Keep Developer Mode and the local tunnel enabled. Pair Playlist Move once through Connection setup.
2. Create a shortcut named **Playlist this** in Apple's Shortcuts app. In its Details, enable **Receive What's On Screen**. Accept **Images** as input. Set **If there's no input** to **Stop and Respond**, with a message to open the screenshot in Photos.
3. Add Playlist Move's **Create Spotify Playlist from Image** action. Set **Image** to **Shortcut Input** and **Playlist name** to **Comment Section**, or another new name.
4. Run the shortcut once to grant any system access prompts before recording. It uses the supplied image, without searching your photo library for another image.
5. Open a readable screenshot in Photos and say **Siri, playlist this**. Playlist Move opens, extracts up to five song recommendations, connects to the paired phone, and shows a three-second Cancel countdown. Spotify then opens and the agent creates the playlist.

If a title cannot be read, the app displays the issue instead of starting. Artist names can be supplied in the screenshot or resolved from Spotify results.

The foreground handoff through Playlist Move starts its background work before Spotify opens. Pairing, the tunnel, and system permission prompts are one-time setup for the demo, rather than steps to hide during recording.

Siri invokes the shortcut and passes the image to the app. The app's local model reads the image text and chooses the workflow actions; cell-use observes and controls Spotify through the screen. The shortcut contains the handoff action, not Spotify search-and-add steps.

## Move a playlist

1. Enable Apple Intelligence and finish its model download. Sign in to Spotify and Apple Music, with an active Apple Music subscription.
2. Enable Developer Mode and the local tunnel used by cell-use. Pair Playlist Move through the app's Connection setup section, then connect to this iPhone.
3. Select **Move a playlist**. Enter a playlist name, new destination name, and one or five songs. Or tap **Say your request**, speak, then tap **Use recording**. Check the filled fields before starting. English speech is transcribed on device with SpeechAnalyzer; its language assets download on first use if needed.
4. Optionally paste the playlist's full Spotify link to open it directly. Tap **Move my playlist**. Once background work is ready, Spotify opens automatically. Leave the screen unlocked and in portrait. The app reads the playlist, navigates to Music, and works through the transfer.
5. Return to Playlist Move to inspect the result and export its timeline. Returning during a run stops further input. Use a new destination name for a fresh run.

Start with one song. If you stop a run, inspect the destination playlist before starting another.

## Recording

Use iPhone Screen Recording for readable close-ups, or film the phone with another camera to show your hands away during the actions. Record narration afterward or on the second camera. If using the optional Siri shortcut, test its audio alongside screen recording before the take. Music playback is unnecessary.

The exported JSON includes model-decision timestamps, inference durations, transport acknowledgements and the final inventory. Completion is labeled `agentJudgment`; the report's `verified` list is reserved for separate deterministic checks. Decision timestamps describe when an action was chosen; the runner records when input was accepted. Use these to align captions with footage. Label sped-up sections and keep the original recording.

See [the demo script](demo-script.md) for the shot sequence and narration. Keep the first interaction at normal speed, then label sped-up sections while the remaining tracks move.

Playlist inference and text recognition run on the phone. The music apps use their normal internet connections. The optional Photos shortcut uses Siri for activation. Exporting a timeline is an explicit share action; it contains playlist and song names, but no screenshot files or pairing secrets.

Voice recordings are temporary files deleted after transcription or cancellation. Voice input only fills editable fields; it never starts a transfer. The microphone is released before Spotify opens.

## Development

```sh
swift test --package-path Examples/PlaylistMove
```

`PlaylistMoveCore` contains the inventory, verification rules and grounded actions. `LocalPlaylistAgent` implements `PhoneAgent`; another local model can replace it without changing the transport. The example uses text elements from Vision, rather than sending screenshots to a vision-language model.
