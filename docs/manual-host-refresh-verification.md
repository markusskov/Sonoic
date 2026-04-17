# Manual Host Refresh Verification

Use this checklist when validating room name and bonded setup refresh behavior on device.

## Observe In App

Open `Settings` and watch these sections while testing:

- `Status`
- `Refresh Timing`

The timing rows should only advance on successful refreshes:

- `Player State`
- `Room Name`
- `Bonded Setup`

## 1. Healthy Refresh

With the configured Sonos player online:

1. Open `Rooms` and confirm the current room loads.
2. Open `Settings`.
3. Tap `Refresh From Player`.
4. Confirm these transitions:
   - `Player Refresh` goes to refreshing, then updated
   - `Room Name` goes to loading or stays resolved, then resolved
   - `Bonded Setup` goes to loading or stays resolved, then resolved
5. Confirm all three timing rows advance.

## 2. Failure Does Not Look Successful

Create a temporary failure:

- enter an invalid host
- disconnect the phone from the same network
- or power off the target player briefly

Then:

1. Tap `Refresh From Player`.
2. Confirm `Player Refresh` becomes failed.
3. If room identity or topology cannot refresh, confirm their status does not silently return to resolved right away.
4. Confirm the `Room Name` and `Bonded Setup` timing rows do not advance on the failed refresh.

## 3. Retry And Recovery

Restore the healthy setup:

1. Fix the host or reconnect the network.
2. Wait for polling or trigger another manual refresh.
3. Confirm the failed status clears after a real successful refresh.
4. Confirm the timing rows advance only on that successful recovery.
5. Confirm `Rooms` shows the expected room name and bonded products again.

## 4. Rename / Rebond Checks

If possible, validate real metadata changes too:

1. Rename the room in Sonos and wait up to one minute or manually refresh.
2. Confirm `Rooms` updates to the new room name.
3. Add or remove a bonded product, then refresh again.
4. Confirm the bonded setup list updates without restarting Sonoic.
