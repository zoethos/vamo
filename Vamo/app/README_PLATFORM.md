# Platform configuration

## iOS — photo library (Slice 8)

Add to `ios/Runner/Info.plist` before using **Add photo** on the Capture tab:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Vamo needs access to your photos to attach memories to a trip.</string>
```

## Deep links

See [README_DEEP_LINKS.md](README_DEEP_LINKS.md).
