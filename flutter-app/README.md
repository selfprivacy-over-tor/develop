# SelfPrivacy Flutter App (Tor-Modified)

This is the SelfPrivacy Flutter app modified to work with Tor hidden services (.onion addresses).

## Modifications Made for Tor Support

The following files were modified to enable .onion domain connectivity:

### 1. `lib/logic/api_maps/graphql_maps/graphql_api_map.dart`
- Routes .onion requests through SOCKS5 proxy (port 9050)
- Disables TLS certificate verification for .onion (Tor provides encryption)

### 2. `lib/logic/api_maps/rest_maps/rest_api_map.dart`
- Same SOCKS5 proxy routing for REST API calls

### 3. `lib/logic/cubit/server_installation/server_installation_repository.dart`
- Skips DNS lookup for .onion domains (Tor handles routing internally)
- Skips provider token requirements for .onion domains

### 4. `lib/logic/cubit/server_installation/server_installation_cubit.dart`
- Auto-completes recovery flow for .onion domains (skips Hetzner/Backblaze prompts)

### 5. `lib/logic/cubit/server_installation/server_installation_state.dart`
- Handles null DNS API token for .onion domains

## Prerequisites

### For Linux Desktop

```bash
# Install Flutter
# See: https://docs.flutter.dev/get-started/install/linux

# Install Linux desktop dependencies (Ubuntu/Debian)
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev

# Install and start Tor SOCKS proxy
sudo apt-get install tor
```

### For Android

- Android SDK and Android Studio
- Tor proxy app (Orbot) on the Android device, OR
- Host Tor proxy accessible to emulator

## D. Running the Linux Desktop App (With Logs)

### Step 1: Start Tor SOCKS Proxy on Host

```bash
# Option 1: Use system Tor
sudo systemctl start tor

# Option 2: Run Tor with custom config
cat > /tmp/user-torrc << 'EOF'
SocksPort 9050
Log notice stdout
EOF
tor -f /tmp/user-torrc &
```

Verify Tor is running:
```bash
curl --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
```

### Step 2: Run Flutter App with Logs

```bash
cd selfprivacy.org.app
flutter pub get
flutter run -d linux --verbose 2>&1 | tee /tmp/flutter-app.log
```

### Step 3: Connect to Backend

In the app:
1. Choose "I already have a server" (recovery flow)
2. Enter your .onion address: `YOUR_ONION_ADDRESS.onion`
3. Enter recovery key (18-word BIP39 mnemonic)

**Note:** Copy/paste may not work in Flutter Linux desktop. Type manually if needed.

### Viewing Logs

```bash
# Live logs during runtime (verbose)
# Already shown in terminal if using command above

# Or tail the log file
tail -f /tmp/flutter-app.log

# Search for GraphQL responses
grep "GraphQL Response" /tmp/flutter-app.log

# Search for errors
grep -i error /tmp/flutter-app.log
```

## E. Building and Running Android APK

The Android app is built from the same Flutter source code.

### Build Debug APK

```bash
cd selfprivacy.org.app
flutter build apk --debug --flavor fdroid
```

Output: `build/app/outputs/flutter-apk/app-fdroid-debug.apk`

### Build Release APK

```bash
flutter build apk --release --flavor fdroid
```

### Install on Device

```bash
adb install build/app/outputs/flutter-apk/app-fdroid-debug.apk
```

### Android Tor Setup

For Android to connect to .onion addresses, you need Tor running:

**Option 1: Orbot App**
1. Install Orbot from F-Droid or Play Store
2. Enable "VPN Mode" or configure apps to use SOCKS5 proxy

**Option 2: Modify App for Different Proxy Port**
The app uses port 9050 by default. If Orbot uses a different port (e.g., 9150), you'll need to modify `graphql_api_map.dart` and `rest_api_map.dart`.

### Android Logs

```bash
# View all app logs
adb logcat | grep -i selfprivacy

# View Flutter-specific logs
adb logcat | grep flutter
```

## Flavor Options

The app has multiple build flavors:
- `fdroid` - F-Droid release
- `production` - Production release
- `nightly` - Development builds

```bash
# Build specific flavor
flutter build apk --debug --flavor production
flutter build apk --debug --flavor nightly
```

## Troubleshooting

### "Connection refused" or timeout
- Ensure Tor SOCKS proxy is running on port 9050
- Check: `curl --socks5-hostname 127.0.0.1:9050 http://YOUR_ONION.onion/api/version`

### "Invalid recovery key"
- The key must be a 18-word BIP39 mnemonic phrase, NOT a hex string
- Example format: `word1 word2 word3 ... word18`

### DNS lookup errors
- Should not happen with .onion domains (they skip DNS lookup)
- If it does, verify the modifications in `server_installation_repository.dart`

### Copy/paste not working (Linux)
- Known Flutter Linux desktop bug
- Type the recovery key manually

### GraphQL errors in logs
- Check backend logs to see if request arrived
- Verify .onion address is correct
- Ensure backend API is running: `curl --socks5-hostname 127.0.0.1:9050 http://YOUR_ONION.onion/graphql`
