# Deep link setup (Slice 5)

Run `flutter create .` inside `app/` if `android/` and `ios/` folders are missing, then add:

## Android (`android/app/src/main/AndroidManifest.xml`)

Inside the main `<activity>`:

```xml
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="https" android:host="vamo.app" android:pathPrefix="/j" />
</intent-filter>
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="app.vamo" android:host="join" />
</intent-filter>
```

## iOS (`ios/Runner/Info.plist`)

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>app.vamo</string></array>
  </dict>
</array>
```

Add Associated Domains capability: `applinks:vamo.app` for universal links.

## Manual test without universal links

After creating an invite, open in-app route (replace TOKEN):

```
/join?token=TOKEN
```

Or run: `adb shell am start -a android.intent.action.VIEW -d "app.vamo://join?token=TOKEN"`
