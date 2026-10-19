## 0.2.2

* Fixed: when the app stopped reading a response early, such as with `stream.first`, the call stayed pending forever. It's now recorded with the start of the body and the size the server announced.
* Works with app_inspect 0.2.2.

## 0.2.1

* Added an example.
* Documented the AppInspectHttpClient constructor.

## 0.2.0

* Renamed from net_lens_http. The client is now AppInspectHttpClient.
* Works with app_inspect 0.2.0.

## 0.1.0

* First release.
