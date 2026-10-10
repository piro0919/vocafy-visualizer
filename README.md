# Vocafy Visualizer

A companion app for [Vocafy](https://vocafy.kkweb.io/). It draws bars that move with the
song playing in Chrome, in a window of its own.

The songs on Vocafy play inside YouTube's and Niconico's embedded players, which a web page
cannot listen to. The app listens to Chrome's audio from outside the browser instead and
turns it into 32 bars. Nothing is recorded or sent anywhere.

`macos/` holds the macOS app. A Windows version will follow in `windows/`. Both follow
[docs/spectrum.md](docs/spectrum.md).

## macOS

Requires macOS 14.2 or later on Apple silicon.

On first launch macOS asks for permission to record audio. That is the permission Core Audio
needs to tap Chrome's output. The app is signed only by itself, not notarized by Apple, so the
first launch is refused; open it once from the right-click menu in Finder, or clear the
quarantine flag:

```
xattr -dr com.apple.quarantine "/Applications/VocafyVisualizer.app"
```

### Building

```
cd macos
./scripts/build.sh                                         # dist/VocafyVisualizer.app
./dist/VocafyVisualizer.app/Contents/MacOS/VocafyVisualizer --selftest
./scripts/dmg.sh                                           # dist/VocafyVisualizer-<version>.dmg
```

Only the Command Line Tools are needed. Formatting is checked with
`swift format lint --strict -r Sources`.

## License

MIT
