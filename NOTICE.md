# Notice

This repository is an **independent, unofficial clean-room study**. It is not
produced by, endorsed by, affiliated with, or connected to TrellisWM, its
author, or the `trelliswm.app` website.

## What this is

A specification-verification exercise following the Study → Build → Check →
Ready method described by `storytold/craft-anything`. The aim was to derive and
independently re-implement the *observable* layout model of a window manager
that the author of this repository has legitimately installed on their own
Mac. It is a study with an evidence ledger, confidence levels and explicit
limitations — not a replacement for, or a derivative build of, the subject.

## Provenance of `capture/`

Everything under `capture/` is one of:

- public documentation and metadata that ships with the app (`Info.plist`,
  `ReleaseSettings.json`);
- the app's own persisted layout documents and runtime log from the repository
  owner's machine, **redacted** — all ids, window titles, bundle IDs and app
  names are replaced with `<id>` / `<redacted>` before being written;
- symbol names visible via `/usr/bin/strings`, used only as terminology hints
  and never as proof of behaviour.

No source code, disassembly, decompilation, artwork, icons, wallpapers,
tutorial assets or localized prose from the subject is reproduced here.
`capture/info-plist.json` retains the subject's copyright line solely as a
factual metadata field; it does not imply permission, endorsement or
affiliation. Licensing, trial and activation logic were deliberately out of
scope. See `craft.json` → `boundaries`.

## Trademarks

"TrellisWM" and any related marks belong to their respective owner. They are
used here only to identify the software being studied (nominative use). The
independent implementation under `app/` does not reuse the subject's bundle
identifier, URL-scheme owner name, or product name in shipped code.

## Licensing

This repository ships **no LICENSE file**. Under GitHub's default terms the
original material here is therefore "all rights reserved": readers may view
and fork it, but no reuse rights are granted. If reuse is intended, add a
LICENSE explicitly.

Nothing in this repository grants any rights to the subject software, whose
own license terms continue to apply.

## Limitations

See `README.md` §5, `investigation.cany/questions.md` (Q13 inference, Q14
unknown, Q16 ambiguity) and `inbox/unspecified.md` for what was deliberately
left unspecified. Claims in this repository are scoped to what was actually
observed on one machine at one point in time.
