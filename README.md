# NetLens

A network inspector for Flutter that QC can use on their own: see the API calls of each screen, find what failed or was slow, and copy a call as cURL for the backend team, right inside the app.

| Package | What it is |
| --- | --- |
| [net_lens](packages/net_lens) | The inspector: bubble, call list, details, masking |
| [net_lens_dio](packages/net_lens_dio) | Captures Dio requests |
| [net_lens_http](packages/net_lens_http) | Captures package:http requests |
| [example](packages/net_lens/example) | Demo shop app |

## Work on it

This is a pub workspace, so one `flutter pub get` covers every package.

```sh
flutter pub get
flutter analyze packages
cd packages/net_lens && flutter test
```
