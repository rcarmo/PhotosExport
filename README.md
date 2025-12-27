# PhotosExport

![Why I wrote this](docs/PhotosExport-256.png)

`PhotosExport` is a small macOS command-line tool that exports **Apple Photos** library assets to the filesystem, and that I developed out of frustration with Shortcuts’ limited (i.e., non-existent) Photos export capabilities and the brokenness of AppleScript-based solutions.

It is intentionally opinionated:

- Exports **assets from a complete calendar year** (current year by default).
- For each asset, exports **all available `PHAssetResource`s** (including originals, `FullSizeRender` resources, Live Photo paired video resources, adjustment data, brush stroke retouches, etc.), when present.
- Writes into a simple `YYYY/MM` folder hierarchy.
- Uses a deterministic timestamp-based naming convention.

## Requirements

- macOS 13+
- Swift (via Xcode / Command Line Tools)

## Permissions (macOS Photos)

This tool uses the Photos framework and needs permission to read your Photos library.

If you run it from Terminal, macOS typically associates the Photos permission with **Terminal** (or your terminal app). Enable it in:

System Settings → Privacy & Security → Photos

If permission is denied, the tool will exit before exporting.

## Output location

Exports go under:

- `~/Pictures/Exports/YYYY/MM/`

An error log is written to:

- `~/Pictures/Exports/export_errors.log`

## Filenames

Each exported resource file is named:

- `YYYYMMDDHHMMSSx.ext`

Where:

- `YYYYMMDDHHMMSS` comes from the asset `creationDate`.
- `x` is only added **when needed to avoid collisions**; it is a lowercase letter (`a`–`z`) derived from a deterministic hash of the resource’s name plus stable metadata (type/UTI/dimensions/etc.).
- If multiple resources would still collide, the letter is advanced (`…a`, `…b`, …) until unique.
- File extensions are always lowercased.

## Metadata sidecars

If you pass:

- `PhotosExport --metadata`

…the exporter will write a JSON sidecar next to the exported files for each asset.

What it contains (high level):

- Asset identifiers and basic properties (type/subtypes, dimensions, duration, favorite/hidden flags, timestamps).
- Location data (if present) and a best-effort reverse-geocoded placemark.
- A list of exported resources for that asset (type/UTI/original filename/exported filename/path, plus basic file stats).
- Where available, additional Photos/AVFoundation metadata and image properties (e.g., EXIF/TIFF/GPS/IPTC/XMP dictionaries).

Notes:

- Sidecar filenames use the same timestamp-based naming scheme and collision handling as exported resources.
- This can include sensitive data (precise location + placenames, camera serials, etc.). Treat the output folder accordingly.

## Logging

- By default, a detailed progress log is written to `stderr` as it:
  - creates folders,
  - enumerates assets,
  - enumerates resources per asset,
  - and writes each resource to disk.

To write the progress log to a file instead:

- `PhotosExport --log-file /path/to/export.log`

## Incremental runs

If you want to avoid re-downloading/re-writing files, use:

- `PhotosExport --incremental`

By default, the exporter will **overwrite existing files** at the destination path.

With `--incremental`, the exporter will instead **skip any resource whose destination filename already exists**.

## Year override

By default, the exporter processes assets from the current calendar year.

To override:

- `PhotosExport --year 2024`

The year must be a 4-digit value between 1970 and 9999, inclusive. I briefly considered supporting date ranges, but decided against it for simplicity, and I suspect Mankind might change calendars before needing that.

## Build / Run

There’s a `Makefile` with self-documenting targets:

- `make` (shows help)
- `make build`
- `make run ARGS='--log-file /tmp/photosexport.log'`
- `make lint`
- `make test`

You can also run via SwiftPM directly:

- `swift build -c release`
- `./.build/release/PhotosExport`

If you’re building this with Swift 6 strict concurrency enabled: yes, it can be nearly as unpalatable as AppleScript.

## Notes

- `PHAssetResourceRequestOptions.isNetworkAccessAllowed` is enabled, so items stored in iCloud may be downloaded during export.
- “True originals” are exported to the extent that Photos exposes them as `PHAssetResource`s; some assets may only have rendered derivatives available.
