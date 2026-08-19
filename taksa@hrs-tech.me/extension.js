/* Taksa — a GNOME Shell extension.
 *
 * SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A dachshund digs into a burrow: the more of the Claude Code usage limit is
 * spent, the further it disappears past the bottom-left corner of the screen —
 * and the further it emerges from the top-right one.
 *
 * There is no separate gauge: the dog's own length is the scale. The share of
 * its body sticking out at the top right is the share of the limit that is
 * gone; the part still visible at the bottom left is exactly what is left, so
 * the two halves always add up to one whole dog.
 *
 *   0%     the dog is fully visible at the bottom left, nothing at the top
 *   50%    half of it is left below, the other half has surfaced above
 *   100%   nothing below, the whole dog is up top — the limit is used up
 *
 * This file is the canonical build for GNOME Shell 45+ (ESM). The code between
 * the CORE START / CORE END markers contains nothing Shell-version specific and
 * is reused by build-legacy.sh for GNOME 43/44.
 */

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GdkPixbuf from 'gi://GdkPixbuf';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// ==== CORE START ====

// Size of the drawn fallback figure, and the aspect ratio used when no PNG
// ships with the extension.
const PLACEHOLDER_W = 160;
const PLACEHOLDER_H = 60;

// On-screen size of the dog: a fraction of the monitor width, clamped to a
// sane range. The height follows from the image's aspect ratio.
const FIGURE_W_FRACTION = 0.2;
const FIGURE_W_MIN = 200;
const FIGURE_W_MAX = 900;

const BOTTOM_MARGIN = 6; // gap under the lower dog, in unscaled pixels
const PANEL_GAP = 8;     // gap between the panel and the upper dog

const MOVE_MS = 2500;        // how long the dog takes to crawl to a new spot
const DEBOUNCE_MS = 400;     // Gio.FileMonitor fires a burst per single write
const POLL_S = 300;          // safety net in case the file monitor misses a write
const STALE_S = 2 * 60 * 60; // state files older than two hours are ignored

const MAX_STATE_BYTES = 64 * 1024; // anything larger is not our state file
const ENUMERATE_BATCH = 32;

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

function scaleFactor() {
    return St.ThemeContext.get_for_stage(global.stage).scale_factor;
}

/* Wraps a GIO *_async / *_finish pair in a promise. Doing it here instead of
 * with Gio._promisify keeps us from patching shared GObject prototypes. */
function ioTask(object, asyncName, finishName, ...args) {
    return new Promise((resolve, reject) => {
        object[asyncName](...args, (_source, result) => {
            try {
                resolve(object[finishName](result));
            } catch (error) {
                reject(error);
            }
        });
    });
}

function isCancelled(error) {
    return error instanceof GLib.Error &&
        error.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED);
}

function figurePath(extensionPath) {
    const png = GLib.build_filenamev([extensionPath, 'taksa.png']);
    return GLib.file_test(png, GLib.FileTest.EXISTS) ? png : null;
}

/* Aspect ratio of the figure: taken from the image itself when there is one,
 * otherwise from the fallback drawing. get_file_info() only reads the PNG
 * header, it does not decode the image. */
function figureAspect(extensionPath) {
    const png = figurePath(extensionPath);
    if (png) {
        try {
            const [, width, height] = GdkPixbuf.Pixbuf.get_file_info(png);
            if (width > 0 && height > 0)
                return width / height;
        } catch (error) {
            logError(error, 'Taksa: cannot read the size of taksa.png');
        }
    }
    return PLACEHOLDER_W / PLACEHOLDER_H;
}

/* The one place where the figure itself is created. If taksa.png sits next to
 * extension.js it is used, otherwise the fallback is drawn. Replacing the
 * artwork means dropping in a file, not touching the code.
 *
 * The dog faces right: tail on the left, nose on the right. The size is set
 * from the outside, in _relayout(). */
function createFigureActor(extensionPath) {
    const png = figurePath(extensionPath);
    if (png) {
        const image = new St.Widget({style_class: 'taksa-figure'});
        image.set_style(
            `background-image: url("${GLib.filename_to_uri(png, null)}"); ` +
            'background-size: contain;');
        return image;
    }

    const area = new St.DrawingArea({style_class: 'taksa-figure'});
    area.connect('repaint', self => drawFallbackFigure(self));
    return area;
}

function roundedRect(cr, x, y, width, height, radius) {
    const HALF_PI = Math.PI / 2;
    cr.newSubPath();
    cr.arc(x + width - radius, y + radius, radius, -HALF_PI, 0);
    cr.arc(x + width - radius, y + height - radius, radius, 0, HALF_PI);
    cr.arc(x + radius, y + height - radius, radius, HALF_PI, Math.PI);
    cr.arc(x + radius, y + radius, radius, Math.PI, 3 * HALF_PI);
    cr.closePath();
}

/* Fallback for a missing PNG: a black dachshund facing right. The tail is on
 * the left — it is the first thing to slip past the left edge at the bottom and
 * the first thing to reappear at the top right. */
function drawFallbackFigure(area) {
    const cr = area.get_context();
    const [width, height] = area.get_surface_size();
    cr.scale(width / PLACEHOLDER_W, height / PLACEHOLDER_H);

    const BLACK = [0.11, 0.1, 0.11];
    const TAN = [0.72, 0.5, 0.22];

    // tail
    cr.setSourceRGBA(BLACK[0], BLACK[1], BLACK[2], 1);
    cr.setLineWidth(5);
    cr.moveTo(20, 28);
    cr.curveTo(12, 24, 6, 20, 4, 12);
    cr.stroke();

    // paws
    cr.setSourceRGBA(TAN[0], TAN[1], TAN[2], 1);
    roundedRect(cr, 30, 42, 11, 16, 5);
    cr.fill();
    roundedRect(cr, 96, 42, 11, 16, 5);
    cr.fill();

    // body
    cr.setSourceRGBA(BLACK[0], BLACK[1], BLACK[2], 1);
    roundedRect(cr, 16, 22, 108, 26, 13);
    cr.fill();

    // head
    cr.arc(128, 30, 16, 0, 2 * Math.PI);
    cr.fill();

    // muzzle
    roundedRect(cr, 138, 28, 20, 12, 6);
    cr.fill();

    // ear
    roundedRect(cr, 118, 24, 14, 26, 7);
    cr.fill();

    // nose
    cr.setSourceRGBA(0.05, 0.05, 0.05, 1);
    cr.arc(156, 32, 3.5, 0, 2 * Math.PI);
    cr.fill();

    // eye
    cr.setSourceRGBA(1, 1, 1, 1);
    cr.arc(133, 26, 4.5, 0, 2 * Math.PI);
    cr.fill();
    cr.setSourceRGBA(0.05, 0.05, 0.05, 1);
    cr.arc(134, 26, 2.4, 0, 2 * Math.PI);
    cr.fill();

    // cap
    cr.setSourceRGBA(0.96, 0.96, 0.94, 1);
    roundedRect(cr, 120, 4, 24, 14, 7);
    cr.fill();
    cr.setSourceRGBA(0.85, 0.2, 0.25, 1);
    cr.arc(132, 11, 3, 0, 2 * Math.PI);
    cr.fill();

    cr.$dispose();
}

/* The extension core. Version agnostic: enable() and disable() are called from
 * the wrapper at the bottom of the file. */
class Taksa {
    constructor(extensionPath) {
        this._extensionPath = extensionPath;
        this._aspect = figureAspect(extensionPath);

        this._bottomFrame = null;
        this._topFrame = null;
        this._bottomFigure = null;
        this._topFigure = null;
        this._indicator = null;
        this._indicatorLabel = null;

        this._figureWidth = PLACEHOLDER_W;
        this._figureHeight = PLACEHOLDER_H;

        this._cancellable = null;
        this._fileMonitor = null;
        this._fileMonitorId = 0;
        this._monitorsChangedId = 0;
        this._panelHeightId = 0;
        this._scaleChangedId = 0;
        this._debounceId = 0;
        this._pollId = 0;

        this._percent = null;
        this._generation = 0;
    }

    enable() {
        this._cancellable = new Gio.Cancellable();

        // Each half lives in its own frame, clipped to the figure's size and
        // parked against a screen corner. The dog inside slides sideways, so
        // whatever leaves the frame is simply cut off.
        this._bottomFigure = createFigureActor(this._extensionPath);
        this._topFigure = createFigureActor(this._extensionPath);
        this._bottomFrame = this._createFrame(this._bottomFigure);
        this._topFrame = this._createFrame(this._topFigure);

        for (const frame of [this._bottomFrame, this._topFrame]) {
            // The frames are non-reactive and stay out of the input region,
            // but neither of those hides them from Clutter.PickMode.ALL, which
            // the overview's drag and drop uses to find a target under the
            // pointer. Without this, dropping a window on a workspace thumbnail
            // would fail wherever a frame overlaps it.
            if (Shell.util_set_hidden_from_pick)
                Shell.util_set_hidden_from_pick(frame, true);

            Main.layoutManager.addChrome(frame, {
                affectsInputRegion: false,
                affectsStruts: false,
                trackFullscreen: true,
            });
        }

        this._indicator = new PanelMenu.Button(0.0, 'Taksa', true);
        this._indicatorLabel = new St.Label({
            style_class: 'taksa-indicator',
            text: '🐕 —',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._indicator.add_child(this._indicatorLabel);
        Main.panel.addToStatusArea('taksa', this._indicator, 0, 'right');

        const dir = this._stateDir();
        // Created up front so the monitor below has something to watch; the
        // writers (statusline-taksa.sh and friends) own the contents.
        GLib.mkdir_with_parents(dir.get_path(), 0o700);

        try {
            this._fileMonitor = dir.monitor_directory(
                Gio.FileMonitorFlags.NONE, null);
            this._fileMonitorId = this._fileMonitor.connect(
                'changed', () => this._queueRefresh());
        } catch (error) {
            logError(error, 'Taksa: cannot watch the state directory');
        }

        this._monitorsChangedId = Main.layoutManager.connect(
            'monitors-changed', () => this._relayout());
        /* The panel has no height yet while the shell is still starting up, and
         * both it and the scale factor change without a monitors-changed. Both
         * feed _relayout(), so both have to be watched or the upper dog ends up
         * behind the panel. */
        this._panelHeightId = Main.layoutManager.panelBox.connect(
            'notify::height', () => this._relayout());
        this._scaleChangedId = St.ThemeContext.get_for_stage(global.stage).connect(
            'notify::scale-factor', () => this._relayout());

        this._pollId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, POLL_S, () => {
                this._refresh(true);
                return GLib.SOURCE_CONTINUE;
            });

        this._relayout();
        this._refresh(false);
    }

    disable() {
        if (this._cancellable) {
            this._cancellable.cancel();
            this._cancellable = null;
        }
        if (this._debounceId) {
            GLib.Source.remove(this._debounceId);
            this._debounceId = 0;
        }
        if (this._pollId) {
            GLib.Source.remove(this._pollId);
            this._pollId = 0;
        }
        if (this._monitorsChangedId) {
            Main.layoutManager.disconnect(this._monitorsChangedId);
            this._monitorsChangedId = 0;
        }
        if (this._panelHeightId) {
            Main.layoutManager.panelBox.disconnect(this._panelHeightId);
            this._panelHeightId = 0;
        }
        if (this._scaleChangedId) {
            St.ThemeContext.get_for_stage(global.stage).disconnect(
                this._scaleChangedId);
            this._scaleChangedId = 0;
        }
        if (this._fileMonitor) {
            if (this._fileMonitorId) {
                this._fileMonitor.disconnect(this._fileMonitorId);
                this._fileMonitorId = 0;
            }
            this._fileMonitor.cancel();
            this._fileMonitor = null;
        }
        for (const figure of [this._bottomFigure, this._topFigure])
            figure?.remove_all_transitions();
        for (const frame of [this._bottomFrame, this._topFrame]) {
            if (!frame)
                continue;
            Main.layoutManager.removeChrome(frame);
            frame.destroy();
        }
        this._bottomFrame = null;
        this._topFrame = null;
        this._bottomFigure = null;
        this._topFigure = null;

        this._indicator?.destroy();
        this._indicator = null;
        this._indicatorLabel = null;

        this._percent = null;
    }

    _createFrame(figure) {
        const frame = new St.Widget({
            style_class: 'taksa-frame',
            clip_to_allocation: true,
            layout_manager: new Clutter.FixedLayout(),
        });
        // The frame's own visibility belongs to the layout manager, which
        // resets it whenever trackFullscreen is re-evaluated. Ours goes on the
        // child: nothing is shown until a usage percentage is actually known.
        figure.visible = false;
        frame.add_child(figure);
        return frame;
    }

    _stateDir() {
        return Gio.File.new_for_path(
            GLib.build_filenamev([GLib.get_user_state_dir(), 'taksa']));
    }

    _queueRefresh() {
        if (this._debounceId)
            GLib.Source.remove(this._debounceId);
        this._debounceId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT, DEBOUNCE_MS, () => {
                this._debounceId = 0;
                this._refresh(true);
                return GLib.SOURCE_REMOVE;
            });
    }

    /* Reads every state file and applies the result. Reads are asynchronous, so
     * a slow or oversized file can never stall the shell; a newer refresh
     * started while one is in flight wins, whatever the completion order. */
    _refresh(animate) {
        const cancellable = this._cancellable;
        if (!cancellable)
            return;

        const generation = ++this._generation;
        this._readPercent(cancellable).then(percent => {
            if (generation === this._generation && cancellable === this._cancellable)
                this._apply(percent, animate);
        }).catch(error => {
            if (!isCancelled(error))
                logError(error, 'Taksa: cannot read the state directory');
        });
    }

    /* Every *.json file in the state directory is an independent source. Stale
     * ones are dropped, and of the rest the largest of five_hour / seven_day
     * wins — the scary number is the limit that runs out first.
     *
     * A file with "override": true beats the others, which is how taksa-test.sh
     * can show 0% while a fresh claude-code.json sits next to it. */
    async _readPercent(cancellable) {
        const dir = this._stateDir();

        let enumerator;
        try {
            enumerator = await ioTask(dir,
                'enumerate_children_async', 'enumerate_children_finish',
                'standard::name,standard::size', Gio.FileQueryInfoFlags.NONE,
                GLib.PRIORITY_DEFAULT, cancellable);
        } catch (error) {
            if (isCancelled(error))
                throw error;
            return null; // no state directory yet — nothing to show
        }

        const now = GLib.get_real_time() / 1000000;
        let best = null;
        let override = null;

        try {
            for (;;) {
                const batch = await ioTask(enumerator,
                    'next_files_async', 'next_files_finish',
                    ENUMERATE_BATCH, GLib.PRIORITY_DEFAULT, cancellable);
                if (batch.length === 0)
                    break;

                for (const info of batch) {
                    const name = info.get_name();
                    if (!name.endsWith('.json') || info.get_size() > MAX_STATE_BYTES)
                        continue;

                    const sample = await this._readSample(
                        dir.get_child(name), cancellable, now);
                    if (sample === null)
                        continue;

                    if (sample.override)
                        override = override === null ? sample.percent : Math.max(override, sample.percent);
                    else
                        best = best === null ? sample.percent : Math.max(best, sample.percent);
                }
            }
        } finally {
            enumerator.close_async(GLib.PRIORITY_DEFAULT, null, (_source, result) => {
                try {
                    enumerator.close_finish(result);
                } catch (error) {
                    if (!isCancelled(error))
                        logError(error, 'Taksa: cannot close the state directory');
                }
            });
        }

        return override ?? best;
    }

    /* One state file: {percent, override} or null if it is unusable or stale. */
    async _readSample(file, cancellable, now) {
        let data;
        try {
            const [, contents] = await ioTask(file,
                'load_contents_async', 'load_contents_finish', cancellable);
            data = JSON.parse(new TextDecoder().decode(contents));
        } catch (error) {
            if (isCancelled(error))
                throw error;
            return null; // unreadable, half-written or not JSON — skip it
        }

        if (typeof data?.updated_at !== 'number')
            return null;
        if (now - data.updated_at > STALE_S)
            return null;

        let percent = null;
        for (const key of ['five_hour', 'seven_day']) {
            const value = data[key];
            if (typeof value === 'number' && Number.isFinite(value))
                percent = percent === null ? value : Math.max(percent, value);
        }
        if (percent === null)
            return null;

        return {percent, override: data.override === true};
    }

    _apply(percent, animate) {
        if (this._indicatorLabel) {
            this._indicatorLabel.text = percent === null
                ? '🐕 —'
                : `🐕 ${Math.round(clamp(percent, 0, 100))}%`;
        }

        /* No data means "unknown", not "0% spent": a new session has not made a
         * request yet, the file went stale, the source disappeared. The dog
         * stays where it was and the indicator honestly shows a dash. Crawling
         * back to the start would look like a limit reset that never happened. */
        if (percent === null)
            return;

        // The very first reading is placed without animation: there is no
        // previous position to crawl away from.
        const known = this._percent !== null;
        const changed = percent !== this._percent;
        this._percent = percent;

        /* A writer re-stamps its state file on every status line, so most
         * refreshes carry the same number as the one before. Re-placing on
         * those would call _move() with animate = false, and that kills the
         * running transition and snaps the dog to its target: a crawl started
         * two seconds ago would end in a jump. */
        if (known && !changed)
            return;

        this._place(animate && changed && known);
    }

    /* Geometry for the current monitor: where the frames sit and how big the
     * dog is. */
    _relayout() {
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor || !this._bottomFrame)
            return;

        const scale = scaleFactor();

        this._figureWidth = Math.round(clamp(monitor.width * FIGURE_W_FRACTION,
            FIGURE_W_MIN * scale, FIGURE_W_MAX * scale));
        this._figureHeight = Math.round(this._figureWidth / this._aspect);

        const topOffset = Math.round(
            Main.layoutManager.panelBox.height + PANEL_GAP * scale);
        const bottomOffset = Math.round(BOTTOM_MARGIN * scale);

        this._bottomFrame.set_size(this._figureWidth, this._figureHeight);
        this._bottomFrame.set_position(monitor.x,
            monitor.y + monitor.height - this._figureHeight - bottomOffset);

        this._topFrame.set_size(this._figureWidth, this._figureHeight);
        this._topFrame.set_position(monitor.x + monitor.width - this._figureWidth,
            monitor.y + topOffset);

        for (const figure of [this._bottomFigure, this._topFigure])
            figure.set_size(this._figureWidth, this._figureHeight);

        this._place(false);
    }

    /* The dog's own length is the scale: the share of its body sticking out of
     * the top-right corner is the share of the limit that is gone, and exactly
     * the missing part is left at the bottom left. Both halves face right, so
     * the rear is the first to leave and the first to come back.
     *
     * A single number defines the cut: `gone`, the length already underground.
     * Both frames are flush with their screen edge, which is what keeps the two
     * halves adding up to one dog. */
    _place(animate) {
        if (!this._bottomFigure)
            return;

        const visible = this._percent !== null;
        this._bottomFigure.visible = visible;
        this._topFigure.visible = visible;
        if (!visible)
            return;

        // Rounded once for both halves, otherwise a pixel wanders at the seam.
        const gone = Math.round(this._figureWidth * clamp(this._percent, 0, 100) / 100);

        // 0%: flush with the left edge, 100%: entirely past it.
        this._move(this._bottomFigure, -gone, animate);
        // 0%: entirely past the right edge, 100%: fully out.
        this._move(this._topFigure, this._figureWidth - gone, animate);
    }

    _move(figure, x, animate) {
        figure.remove_all_transitions();
        if (animate) {
            figure.ease({
                x,
                duration: MOVE_MS,
                mode: Clutter.AnimationMode.EASE_OUT_CUBIC,
            });
        } else {
            figure.set_x(x);
        }
    }
}

// ==== CORE END ====

export default class TaksaExtension extends Extension {
    enable() {
        this._taksa = new Taksa(this.path);
        this._taksa.enable();
    }

    disable() {
        this._taksa?.disable();
        this._taksa = null;
    }
}
