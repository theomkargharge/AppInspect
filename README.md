# AppInspect

A network inspector for Flutter that QC can use on their own: see the API calls of each screen, find what failed or was slow, and copy a call as cURL for the backend team, right inside the app.

| Package | What it is |
| --- | --- |
| [app_inspect](packages/app_inspect) | The inspector: bubble, call list, details, masking |
| [app_inspect_dio](packages/app_inspect_dio) | Captures Dio requests |
| [app_inspect_http](packages/app_inspect_http) | Captures package:http requests |
| [example](packages/app_inspect/example) | Demo shop app |

## Work on it

This is a pub workspace, so one `flutter pub get` covers every package.

```sh
flutter pub get
flutter analyze packages
cd packages/app_inspect && flutter test
```

The tests include a layout sweep: every inspector screen on eight phone and tablet sizes, at three text sizes, must lay out without an overflow.

To look at the inspector's screens as images:

```sh
cd packages/app_inspect && flutter test test/visual_review_test.dart --dart-define=SHOTS_DIR=/tmp/shots
```

On an iOS simulator, from `packages/app_inspect/example`:

```sh
tool/take_store_screenshots.sh   # the pub.dev screenshots, saved as WebP
tool/record_linkedin_demo.sh     # the 1080x1920 demo video, in demo_output/
```
