# Taksa for macOS

The same dachshund as the GNOME extension, as a menu bar app. The dog digs into
a burrow across the bottom-left corner of the screen and comes back out of the
top-right one; the menu bar carries the same number in percent, and the status
line in the terminal shows it too.

Both builds read the same state files and use the same numbers, so a machine
that runs Claude Code needs only one of them installed.

## Requirements

- macOS 13 Ventura or newer
- Xcode command line tools — `xcode-select --install`
- `jq` — `brew install jq`
- Claude Code with a Pro or Max subscription

## Build and install

```bash
cd macos
./build-app.sh --install
open /Applications/Taksa.app
```

`build-app.sh` without `--install` leaves the app in `macos/dist/Taksa.app` and
touches nothing else. It takes the artwork from the GNOME extension next door,
so this directory needs the rest of the repository around it — or a
`TAKSA_FIGURE=/path/to/taksa.png` in front of the command. The build is a universal binary and carries an ad hoc
signature, which is enough to run on the machine that built it — Gatekeeper only
gets in the way for apps downloaded from elsewhere.

The app has no Dock icon and no window: it lives in the menu bar. **Open at
Login** in its menu makes it come back after a restart, **Quit Taksa** stops it.

## The status line

The app does not talk to Claude Code by itself. The numbers come from the same
hook the GNOME build uses:

```bash
mkdir -p ~/.local/bin
cp ../statusline-taksa.sh ~/.local/bin/
chmod +x ~/.local/bin/statusline-taksa.sh
```

and in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.local/bin/statusline-taksa.sh"
  }
}
```

The hook prints the limits in the terminal and writes them to
`~/.local/state/taksa/claude-code.json`. The app watches that folder and moves
the dog. `../taksa-test.sh` drives it without Claude Code — the same commands
work here.

## What macOS does differently

The design is the GNOME one, down to the constants; these are the places where
the platform made the decision:

- The dog is placed inside the screen's **visible frame**, so the menu bar and
  the Dock never cover it. Both halves still sit flush against their corner of
  that area, which is what keeps them adding up to one whole dog.
- The windows float above ordinary windows and stay off the space a full-screen
  app owns, which is how the extension behaves under `trackFullscreen`.
- Sizes are in points, not pixels: AppKit already accounts for a Retina display,
  so the GNOME build's scale factor has no counterpart here.
- The primary screen is the one with the menu bar. Secondary displays are
  deliberately left alone, as on GNOME.

## Working on the app

```bash
swift build                                  # a plain check that it compiles
TAKSA_FIGURE=../taksa@alps/taksa.png swift run
```

`swift run` starts the app straight from the package, without a bundle: it finds
no artwork of its own, which is what `TAKSA_FIGURE` is for, and **Open at Login**
does not work because there is nothing to register.

Log messages go to the unified log:

```bash
log stream --predicate 'process == "Taksa"' --level info
```
