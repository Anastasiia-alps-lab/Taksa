# Taksa

Taksa is a small GNOME Shell extension that tracks Claude Code usage limits. It works with a Pro or Max subscription only.

As the usage limit runs out, the dachshund gradually emerges from the top-right corner of the screen, taking up more and more space.

The extension is published on GNOME Extensions: https://extensions.gnome.org/extension/10735/taksa/

## Demo

<p align="center">
  <img src="assets/demo01.gif" alt="Taksa_demo" width="700">
</p>

## Requirements

- GNOME Shell 43 or newer
- `jq`
- Claude Code

## Installation

Get the files:

```bash
git clone https://github.com/Anastasiia-alps-lab/Taksa.git
cd Taksa
```

Check which GNOME Shell you are on, the next step depends on it:

```bash
gnome-shell --version
```

Copy the extension to the user extensions folder.

For GNOME Shell 45 and newer:

```bash
mkdir -p ~/.local/share/gnome-shell/extensions
cp -r taksa@hrs-tech.me ~/.local/share/gnome-shell/extensions/
```

For GNOME Shell 43 and 44 the build is a separate one, put it together first:

```bash
./build-legacy.sh
mkdir -p ~/.local/share/gnome-shell/extensions
cp -r taksa-legacy@hrs-tech.me ~/.local/share/gnome-shell/extensions/
```

Restart the shell so it picks up the new folder. On X11 press `Alt+F2`, type `r` and press Enter. On Wayland log out and log back in.

Turn the extension on:

```bash
gnome-extensions enable taksa@hrs-tech.me
```

On GNOME 43 and 44 the name is `taksa-legacy@hrs-tech.me`.

## Usage

The extension does not talk to Claude Code by itself. The numbers come from a status line hook that Claude Code runs on every message.

Put the hook somewhere on your disk:

```bash
mkdir -p ~/.local/bin
cp statusline-taksa.sh ~/.local/bin/
chmod +x ~/.local/bin/statusline-taksa.sh
```

Add it to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.local/bin/statusline-taksa.sh"
  }
}
```

Start Claude Code and send anything. The hook prints the limits in the terminal and writes them to `~/.local/state/taksa/claude-code.json`. The extension watches that folder and moves the dog.

The dog itself is the scale. Whatever sticks out of the top-right corner is the share already spent; the rest is still lying in the bottom-left corner. The panel shows the same number in percent. Two limits are counted, the five hour one and the seven day one, and the bigger of the two wins.

Until the first reading arrives nothing is drawn and the panel shows a dash. That is not zero, it only means there is no data yet.

To see how it looks without waiting for real usage:

```bash
./taksa-test.sh 0        # whole dog at the bottom left
./taksa-test.sh 75       # three quarters spent
./taksa-test.sh crawl    # walk from 0 to 100
./taksa-test.sh off      # park the test value, back to real data
./taksa-test.sh on       # bring the parked value back
./taksa-test.sh clear    # delete the test value, back to real data
```

While a test value is set it overrides the live numbers, so the dog stays put no matter what Claude Code reports. Run `off` or `clear` to hand control back.

## Feedback

Taksa is still early. Found a bug or have an idea: open an issue.

## License

GPL-3.0
