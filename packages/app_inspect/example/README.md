# AppInspect demo

A small shop app with AppInspect installed. It calls [dummyjson.com](https://dummyjson.com), a free fake REST API.

```sh
flutter run
```

Things to try:

- On the Shop tab, a 500 happens quietly in the background. The bubble turns red.
- Open a product: one call is slow and one is repeated three times. Both get flagged.
- Tap "Missing product (404)" or "Timeout" for failures in plain words.
- On a product, tap "Add to cart". The app only says "Something went wrong", but AppInspect shows the server answered 201 and names the field the app failed to read.
- Open the Logs tab to see debugPrint, print and errors, tagged with their screen.
- Switch tabs and come back: the bubble keeps counting each tab's own calls.
- On the Account tab, sign in with the demo account. The password, the tokens and the Authorization header are masked.
