# iOS Home Widget Setup

The Flutter side is prepared for an iOS home widget with these identifiers:

- Widget kind: `TypeSyncUpcomingWidget`
- App Group: `group.de.khonager.typesync`

The remaining iOS work needs to be done in Xcode because WidgetKit widgets are
separate native targets.

## 1. Install pods

From the project root:

```bash
cd ios
pod install
```

## 2. Add a Widget Extension target

In Xcode:

1. Open `ios/Runner.xcworkspace`
2. Choose `File` -> `New` -> `Target...`
3. Select `Widget Extension`
4. Name it `TypeSyncUpcomingWidget`
5. Keep it in Swift / SwiftUI

## 3. Enable App Groups

Enable App Groups for both:

- `Runner`
- `TypeSyncUpcomingWidget`

Add:

- `group.de.khonager.typesync`

## 4. Add the home_widget pod to the extension target

Update `ios/Podfile` by adding:

```ruby
target 'TypeSyncUpcomingWidget' do
  inherit! :search_paths
  pod 'home_widget', :path => '.symlinks/plugins/home_widget/ios'
end
```

Then run:

```bash
cd ios
pod install
```

## 5. Build the widget UI

Use the `home_widget` SwiftUI helpers in the extension to read the rendered
image and refresh the timeline for the widget kind `TypeSyncUpcomingWidget`.

The Flutter app already updates:

- the rendered widget image
- placeholder title/subtitle
- the widget refresh trigger

So the native extension mostly needs to display that shared image and link back
into the app.
