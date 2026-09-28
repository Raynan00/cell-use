# iPhone automation demos

Complete [setup](setup.md) first. Use empty test content, keep portrait rotation
locked, disconnect USB and keep the phone unlocked. The included scripted agents demonstrate observation, action delivery and
sequencing before you connect your own model.

## Swipe

1. Open Settings on its main scrollable list, near the top.
2. Return to cell-use, select **Connect**, wait for input readiness, then tap
   **Arm swipe test**.
3. Switch directly to Settings and leave the screen untouched for about 15 seconds.
4. Return to cell-use. Inspect the resulting screenshot. Record confirmation only
   if you saw the list scroll. The runner should show a swipe followed by finish.

## Text

1. Create an empty Notes draft, tap its editable body and leave the cursor active
   with an English (US) keyboard layout.
2. Return to cell-use, connect, tap **Arm text test**, then switch directly to Notes.
3. Leave the phone untouched for about 18 seconds. Inspect the inserted test text
   and the final screenshot before confirming success in cell-use.

The provider uses a fixed printable-ASCII test string. Use the English (US) layout and focus the field before starting.

## Ordered multi-step input

1. Open Calculator in Basic portrait mode showing `0`.
2. Connect in cell-use, switch to Calculator briefly to capture it, then return.
3. Use the captured-screen target picker to select the center of the `7` key.
4. Tap **Arm agent demo**, switch back to Calculator and leave it untouched.
5. Expect `0 → 7 → 77`: the client requests tap, wait, tap, finish, with a new
   screenshot for each decision. Inspect the saved images and confirm only the
   sequence you actually observed.

For the extended variant, prepare the selected target, use **Extended run** and
arm the agent demo promptly after connection. The first decision is delayed until
at least 60 continuous background seconds. The run combines 60 captures and four
agent decisions with real progress reporting. Remain in Calculator until it ends
or the system cancels it. The reference job captures 60 frames and reports progress as work completes.

## A clear launch recording

Record the physical phone with a second camera so viewers can see hands off the
screen and the disconnected cable. Show setup requirements, start a run, show the
target app changing, then show the completed report. Label the client **scripted**
and describe cell-use as the library handling phone control. Keep account details and private
content out of the shot.
