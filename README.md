# PortPig

PortPig is a lightweight macOS menu bar app for checking local listening TCP
ports and killing the owning process.

## Requirements

- macOS 13 or later

## Install with Homebrew

```sh
brew install --cask lawnect/tap/portpig
```

To upgrade or remove PortPig later:

```sh
brew upgrade --cask portpig
brew uninstall --cask portpig
```

## Development

Development requires Xcode command line tools with Swift 6 or later.

```sh
make build
make test
make run
```

`make run` launches the app as an accessory app. It does not create a normal window.

### Xcode

Open the direct-distribution macOS app project:

```sh
open PortPig.xcodeproj
```

Select the `PortPig` scheme and `My Mac`, then use Run or Test normally. The
project keeps App Sandbox disabled because the app needs to inspect and terminate
local processes, and enables Hardened Runtime for Developer ID distribution.

Before creating a distributable archive, select the `PortPig` target, open
Signing & Capabilities, choose your Apple Developer team, and confirm the bundle
identifier. Then choose Product > Archive and, in Organizer, use Distribute App >
Developer ID. Xcode can upload the archive for notarization and export the signed
app.

### Service Logos

Service logo SVGs are generated from the
[`@iconify-json/logos`](https://www.npmjs.com/package/@iconify-json/logos)
package, which packages the
[SVG Logos](https://github.com/gilbarbara/logos) collection. The collection is
released under CC0 1.0. The selected SVG assets were exported from
`@iconify-json/logos@1.2.13` and are committed directly to the repository; Node.js
and pnpm are not required to build or run the macOS app.

`caddy.svg`, `elixir.svg`, `rails.svg`, and `rust.svg` remain sourced from
[Simple Icons](https://simpleicons.org/) because the SVG Logos alternatives are
missing or unsuitable at the app's 22-point display size. See
[`ATTRIBUTION.md`](Sources/PortPig/Resources/ServiceIcons/ATTRIBUTION.md)
for details. Individual logos remain subject to their owners' trademark and brand
guidelines.

## App Bundle

```sh
make bundle
open ".build/app/PortPig.app"
```

The bundle uses `LSUIElement=true`, so the app runs without a Dock icon.
Both the Xcode project and the `make bundle` path compile
`Resources/AppIcon.icon` with Apple's asset compiler. This places the generated
`AppIcon.icns` and `Assets.car` in the application bundle.

To create a visible distributable copy:

```sh
make dist
```

This writes `dist/PortPig.app`. Remove it after use if you do not want Spotlight to show a duplicate app.

## Release

Release archives are universal macOS apps signed by Xcode with Lawnnect's
cloud-managed Developer ID certificate and notarized by Apple. The notarization
credential is read from the `portpig` keychain profile.

Register that credential once, using the new account's Apple Developer Team ID
and an app-specific password for its Apple ID:

```sh
xcrun notarytool store-credentials "portpig" --team-id "K8R5WLB763"
```

Then build, notarize, staple, verify, and publish the current version:

```sh
make publish
```

The version comes from `Resources/Info.plist`. `make publish` requires a clean
working tree whose current commit is already pushed to `origin/main`.

## Install As An App

```sh
make install
open "$HOME/Applications/PortPig.app"
```

After installation, open it from `~/Applications`, Finder, Spotlight, or Launchpad.

For a one-command build, install, and launch:

```sh
make launch
```

## Implementation Notes

- Port discovery uses `lsof` for TCP listeners, parent PIDs, and user IDs, then enriches them with executable paths and bounded ancestry from `ps`.
- `All` always shows every listening port. The default saved `Dev` filter includes web servers, databases, caches, messaging services, containers, mobile tools, and development runtimes.
- Create and edit saved filters from the `+` button. Filters can combine service categories, process or app names, owner, termination status, local/network exposure, and a port range.
- Filter rules are persisted between launches. Up to two saved filters can be pinned beside `All` for quick access; additional filters remain available in the filter manager.
- Process identity takes precedence over a conventional port, and ambiguous matches are labeled in the UI with their classification reason available on hover.
- Executable paths identify compiled Rust, Go, SwiftPM, Node module, and Python virtual-environment processes. Commands for listening processes and their bounded ancestry are inspected in memory to retain only a sanitized web-tool hint; full command-line arguments are discarded.
- JavaScript project working directories are inspected for a bounded `package.json`; only a framework hint such as SvelteKit, React, Vue, or SolidStart is retained.
- Bundled application paths and process ancestry distinguish Dia, Serena, Codex, Zed, Figma, Tailscale, VS Code, and Cursor helpers; installed application icons are used when available.
- Process termination uses `/bin/kill -9 <PID>` only for verified processes owned by the current user. Administrator, other-user, macOS, and unknown-owner processes are protected in the UI.
- The UI is an `NSStatusBar` item backed by an `NSPopover` with SwiftUI content.

## License

PortPig is available under the [MIT License](LICENSE). Third-party service
logos remain subject to the terms and trademark guidelines documented in
[`ATTRIBUTION.md`](Sources/PortPig/Resources/ServiceIcons/ATTRIBUTION.md).
