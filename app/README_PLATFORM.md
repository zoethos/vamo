# Platform configuration

## iOS — photo library (Slice 8)

Add to `ios/Runner/Info.plist` before using **Add photo** on the Capture tab:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Vamo needs access to your photos to attach memories to a trip.</string>
```

Photo location metadata is only read when the user enables **Tag captures with
location** in Profile. On iOS this requires photo library access to the selected
asset; limited-library picks may not expose GPS metadata.

## Android — media location (TripMap groundwork)

The app declares `ACCESS_MEDIA_LOCATION` so Android can expose EXIF GPS data for
selected media when the user enables **Tag captures with location**.

## Deep links

See [README_DEEP_LINKS.md](README_DEEP_LINKS.md).
