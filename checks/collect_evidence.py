#!/usr/bin/env python3
"""Re-derive the capture/ evidence set from the subject installed on this Mac.

Read-only. Never writes to the subject's bundle or Library. All string values
that could identify a window, document, app or person are scrubbed before they
land in capture/. Re-run after a subject update to refresh the study.
"""
from __future__ import annotations

import collections
import json
import os
import plistlib
import re
import subprocess
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
CAP = BASE / "capture"
APP = Path("/Applications/TrellisWM.app")
SUPPORT = Path.home() / "Library/Application Support/TrellisWM"
LOG = Path.home() / "Library/Logs/TrellisWM.log"

SCRUB_KEYS = {"titles", "tokens", "appName", "bundleID", "document", "selected", "world", "seat", "template"}
ID_RE = re.compile(r"^(?:s-|t-|w\d|split-|panel-|[0-9a-f]{8}-)")


def scrub(value, key: str | None = None):
    if isinstance(value, dict):
        return {k: ("<redacted>" if k in SCRUB_KEYS else scrub(v, k)) for k, v in value.items()}
    if isinstance(value, list):
        return [scrub(v) for v in value]
    if isinstance(value, str):
        if ID_RE.match(value) or len(value) > 24:
            return "<id>"
        return value
    return value


def write(name: str, obj) -> None:
    (CAP / name).write_text(json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"  wrote capture/{name}")


def collect_metadata() -> dict:
    plist = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
    keep = [
        "CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
        "CFBundleExecutable", "CFBundleURLTypes", "LSMinimumSystemVersion",
        "LSUIElement", "NSHumanReadableCopyright", "SUFeedURL",
    ]
    info = {k: plist[k] for k in keep if k in plist}
    write("info-plist.json", info)
    settings = json.loads((APP / "Contents/Resources/ReleaseSettings.json").read_text())
    write("release-defaults.json", settings)
    return settings


def find_splits(node, path=""):
    out = []
    if isinstance(node, dict):
        if node.get("kind") == "split":
            out.append((path, node))
        for k, v in node.items():
            out += find_splits(v, f"{path}.{k}" if path else k)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            out += find_splits(v, f"{path}[{i}]")
    return out


def collect_layout() -> None:
    kinds: collections.Counter = collections.Counter()
    node_keys: dict[str, set[str]] = collections.defaultdict(set)
    samples = []
    top_keys: set[str] = set()
    seat_keys: set[str] = set()

    def scan(node, path=""):
        if isinstance(node, dict):
            kind = node.get("kind")
            if isinstance(kind, str):
                kinds[kind] += 1
                node_keys[kind].update(node.keys())
            for k, v in node.items():
                scan(v, f"{path}.{k}" if path else k)
        elif isinstance(node, list):
            for v in node:
                scan(v, path + "[]")

    for p in sorted(SUPPORT.glob("*.json")):
        try:
            doc = json.loads(p.read_text())
        except (ValueError, OSError):
            continue
        scan(doc)
        if isinstance(doc, dict) and "doc" in doc:
            top_keys.update(doc.keys())
            for seat in doc.get("seats", {}).values():
                if isinstance(seat, dict):
                    seat_keys.update(seat.keys())
        for path, split in find_splits(doc):
            samples.append({"file_kind": "persisted-template", "path": path, "node": scrub(split)})

    schema = {
        "derived_from": "live layout-*.json / arrangement-*.json / departures.json on this Mac",
        "document_version": 2,
        "top_level_keys": sorted(top_keys),
        "node_kinds_observed": dict(kinds),
        "node_keys_by_kind": {k: sorted(v) for k, v in node_keys.items()},
        "seat_keys": sorted(seat_keys),
        "grammar": {
            "Node": "Desktop | Panel | Split",
            "Desktop": {"kind": "desktop", "id": "desktop"},
            "Panel": {"kind": "panel", "id": "string", "views": ["seat-id"], "selected": "seat-id", "tabbed": "bool?"},
            "Split": {"kind": "split", "id": "split-XXXXXX", "axis": "x|y", "children": ["Node"], "weights": ["Double, sums to 1"]},
        },
        "invariants": [
            "Exactly one node with id=='desktop' acts as the floating-window layer.",
            "Split.children.count == Split.weights.count",
            "sum(Split.weights) == 1.0 within floating-point tolerance",
            "Split nodes nest recursively: this is the 'spaces inside spaces' property.",
            "A Panel.views array with >1 element is a tab group; selected points at the visible tab.",
            "framed stores the camera's focus node id. 'desktop' is ALSO the floating-layer leaf; in observed all-floating documents root == desktop, so 'zoomed out' and 'framed Desktop' cannot be distinguished from the data alone (see investigation.cany/questions.md Q16).",
            "floatSizes / seats / dockSpots are keyed by a stable seat id (s-... in layout, w... in arrangement).",
        ],
    }
    write("layout-schema.json", schema)
    # keep two distinct, fully scrubbed tree shapes
    seen, picked = set(), []
    for s in samples:
        sig = json.dumps(s["node"], sort_keys=True)[:120]
        if sig not in seen:
            seen.add(sig)
            picked.append(s)
        if len(picked) == 3:
            break
    write("layout-sample.json", {"trees": picked})


def collect_runtime() -> None:
    if not LOG.exists():
        return
    lines = LOG.read_text(encoding="utf-8", errors="replace").splitlines()
    tags: collections.Counter = collections.Counter()
    motions: collections.Counter = collections.Counter()
    examples: dict[str, str] = {}
    for line in lines:
        m = re.search(r"(?:^|\])\s*([A-Z][A-Z \-]{1,28})\s", line)
        if m:
            tag = m.group(1).strip()
            tags[tag] += 1
            examples.setdefault(tag, re.sub(r"[一-鿿]+", "<display>", line.strip())[:200])
        mo = re.search(r"MOTION\s+(\S+)\s*→\s*(\S+)", line)
        if mo:
            motions[f"{mo.group(1)} → {mo.group(2)}"] += 1
    durations = [float(x) for x in re.findall(r"SETTLED after (\d+) ms", "\n".join(lines))]
    buckets: collections.Counter = collections.Counter()
    for v in durations:
        if v < 100: buckets["<100"] += 1
        elif v < 300: buckets["100-299"] += 1
        elif v < 400: buckets["300-399"] += 1
        elif v < 450: buckets["400-449"] += 1
        elif v < 480: buckets["450-479"] += 1
        elif v < 600: buckets["480-599"] += 1
        else: buckets[">=600"] += 1
    import statistics
    settled = {
        "samples": len(durations),
        "min": min(durations) if durations else None,
        "max": max(durations) if durations else None,
        "mean": round(sum(durations) / len(durations), 1) if durations else None,
        "median": statistics.median(durations) if durations else None,
        "buckets": dict(buckets),
        "near_nominal_450_479": buckets["450-479"],
        "note": "The product's nominal 460ms is the modal full layout motion, not the mean: interrupted / quick motions below 100ms pull the mean down. The subject keeps appending to this log, so sample counts drift between captures.",
    }
    write("runtime-events.json", {
        "log_lines": len(lines),
        "event_tags": dict(tags.most_common()),
        "event_examples": examples,
        "motion_transitions": dict(motions.most_common(20)),
        "settled_ms": settled,
        "note": "App names, display names and window titles are redacted; only event vocabulary and timings are kept.",
    })


def collect_symbols() -> None:
    exe = APP / "Contents/MacOS/TrellisWM"
    if not exe.exists():
        return
    strings = subprocess.run(["/usr/bin/strings", "-a", str(exe)], capture_output=True, text=True).stdout.splitlines()
    L = [s.strip() for s in strings if len(s.strip()) >= 4]
    type_re = re.compile(r"^(?:TWM|Trellis|Space|Desk|Window|Tile|Tab|View|Zoom|Camera|Layout|Nest|Frame|Focus|History|Grid|Gap|Pinch|Dock|Float|Group|Overview|Picture|Snapshot|Settings|App|Screen|Display)[A-Z][A-Za-z]{2,40}$")
    ax_re = re.compile(r"^(?:AXUIElement|AXObserver|AXWindow[A-Za-z]*|AXUIElementDestroyed)$")
    types = sorted({s for s in L if type_re.match(s)})
    ax = sorted({s for s in L if ax_re.match(s)})
    frameworks = sorted({s for s in L if s in {"AppKit", "ScreenCaptureKit", "SwiftUI", "QuartzCore", "Carbon", "IOKit"}})
    write("symbols.json", {
        "method": "symbol names only, from /usr/bin/strings; no disassembly, no code copied",
        "counts": {"all_strings": len(L), "type_names": len(types)},
        "type_names": types,
        "accessibility_api": ax,
        "frameworks": frameworks,
        "disclaimer": "Type names are treated as terminology hints only. No implementation detail is asserted from a name alone; every behavioural claim in evidence.md requires a second source.",
    })


def main() -> None:
    print("Collecting observable evidence (read-only)...")
    # NOTE: do not call Path.mkdir() here. This machine brokers Python mkdir()
    # and raises EEXIST even with exist_ok=True when the directory already exists.
    if not CAP.is_dir():
        raise SystemExit(f"missing capture directory: {CAP}")
    collect_metadata()
    collect_layout()
    collect_runtime()
    collect_symbols()
    print("Done.")


if __name__ == "__main__":
    main()
