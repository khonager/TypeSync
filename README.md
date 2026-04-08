# TypeSync

A cross-platform note-taking app with cloud sync, markdown support, and productivity features.

![TypeSync Design](docs/design-preview.png)

## Features

### Core Features
- 📝 **Rich Text Editing** - Markdown-like text formatting with headers, lists, quotes, and code blocks
- 📁 **Folder Organization** - Organize notes in a hierarchical folder structure
- 🏷️ **Tags** - Add tags to notes for easy categorization and filtering
- 🔍 **Search** - Full-text search across all notes
- 📊 **Statistics** - Line and character count displayed in real-time

### Sync & Storage
- ☁️ **Cloud Sync** - Real-time synchronization via Firebase
- 📴 **Offline First** - Works offline with background sync when connected
- 💾 **Storage Tiers**:
  - Free: 1 GB
  - Basic: 5 GB (€1.99/month)
  - Standard: 50 GB (€4.99/month)
  - Premium: 200 GB (€9.99/month)

### Productivity
- 📅 **Calendar** - Test reminders and event scheduling
- 📋 **Timetable** - Weekly class schedule management
- ✅ **Homework Todo** - Task list with due dates and priorities

### Customization
- 🌙 **Dark Mode** - Toggle dark mode or sync with system
- 🎨 **Theme Colors** - Customizable accent colors
- 🖼️ **Background Colors** - Per-file/folder background colors

### Other Features
- 📄 **PDF Insert** - Insert and view PDFs in notes
- 👤 **User Profiles** - Login/register with email
- ⚠️ **Smart Errors** - Expandable error messages (simple by default)

## Getting Started

### Prerequisites

- **Nix** (recommended for development)
- **Flutter SDK** (3.22.0 or later)
- **Firebase CLI** (for deployment)

### Development Setup with Nix (Recommended)

1. **Install Nix** if you haven't already:
   ```bash
   curl -L https://nixos.org/nix/install | sh
   ```

2. **Enable Flakes** (if not already enabled):
   ```bash
   echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
   ```

3. **Enter development environment**:
   ```bash
   cd TypeSync
   nix develop
   ```

   This automatically sets up:
   - Flutter SDK
   - Dart SDK
   - Android SDK with required components
   - Linux desktop build dependencies
   - Node.js (for firebase-tools)

4. **Install dependencies**:
   ```bash
   flutter pub get
   ```

5. **Configure Firebase** (see Firebase Setup section)

6. **Run the app**:
   ```bash
   # Linux desktop
   flutter run -d linux
   
   # Android (connect device or start emulator first)
   flutter run -d android
   ```

### Development Setup without Nix

1. **Install Flutter**: Follow the [official guide](https://docs.flutter.dev/get-started/install)

2. **Install Android Studio** (for Android development)

3. **Install Linux dependencies** (for Linux desktop):
   ```bash
   sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
   ```

4. **Clone and setup**:
   ```bash
   git clone https://github.com/YOUR_USERNAME/TypeSync.git
   cd TypeSync
   flutter pub get
   ```

### Firebase Setup

1. **Install Firebase CLI** (if not already installed):
   ```bash
   npm install -g firebase-tools
   ```

2. **Create a Firebase project**:
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Create a new project
   - Enable Authentication (Email/Password)
   - Enable Cloud Firestore
   - Enable Cloud Storage

2. **Configure Firebase** (recommended method):
   ```bash
   # Install FlutterFire CLI
   dart pub global activate flutterfire_cli
   
   # Configure Firebase
   flutterfire configure
   ```

   This will automatically update `lib/firebase_options.dart` with your project's configuration.

3. **Alternative manual setup**:
   - Download configuration files from Firebase Console
   - For Android: Place `google-services.json` in `android/app/`
   - Update `lib/firebase_options.dart` with your values

4. **Set up Firestore Security Rules**:
   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{userId} {
         allow read, write: if request.auth != null && request.auth.uid == userId;
       }
       match /notes/{noteId} {
         allow read, write: if request.auth != null && 
           request.auth.uid == resource.data.userId;
       }
       match /folders/{folderId} {
         allow read, write: if request.auth != null && 
           request.auth.uid == resource.data.userId;
       }
     }
   }
   ```

5. **Set up Storage Security Rules**:
   ```javascript
   rules_version = '2';
   service firebase.storage {
     match /b/{bucket}/o {
       match /users/{userId}/{allPaths=**} {
         allow read, write: if request.auth != null && request.auth.uid == userId;
       }
     }
   }
   ```

## Building for Release

### Android APK
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

### Android App Bundle (for Play Store)
```bash
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab`

### Linux
```bash
flutter build linux --release
```
Output: `build/linux/x64/release/bundle/`

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── app/
│   └── app.dart              # MaterialApp configuration
├── core/
│   ├── models/               # Data models (Note, Folder, User, etc.)
│   ├── providers/            # State management (Provider)
│   ├── services/             # Business logic (Auth, Sync, Storage)
│   ├── theme/                # App theming
│   └── routes/               # Navigation routes
└── features/
    ├── home/                 # Home screen with folder/file browser
    ├── editor/               # Note editor with rich text
    ├── auth/                 # Login/Register screens
    ├── settings/             # App settings
    ├── calendar/             # Calendar & reminders
    ├── timetable/            # Weekly schedule
    ├── homework/             # Todo list
    ├── profile/              # User profile
    └── subscription/         # Storage plans
```

## GitHub Workflows

The project includes automated CI/CD with GitHub Actions:

### Branches
- **`main`**: Development branch
- **`stable`**: Stable channel branch
- **`unstable`**: Dev builds - updates the `dev` tag

### Automatic Releases
- **Stable releases**: When merged to `stable`, automatically:
  - Validates that `pubspec.yaml` and the latest changelog entry match
  - Creates a new tagged release (`v1.0.0`, `v1.0.1`, etc.) only when the changelog introduces a version newer than the latest version tag
  - Otherwise refreshes the rolling `stable-latest` release/tag on the newest `stable` commit
  - Builds Android APK, AAB, Linux bundle, and Web bundle

- **Dev releases**: When pushed to `unstable`:
  - Updates the `dev` release tag
  - Builds and uploads latest development builds
  - Marked as pre-release

### Manual Workflow
```bash
# Run tests
flutter test

# Check formatting
dart format lib test

# Analyze code
flutter analyze
```

### Changelog Workflow
- Canonical source: `changelog/changelog.yaml`
- Release entry sections:
  - `important` (highlighted at top in-app)
  - `new_features`
  - `fixes_improvements`
  - `notes` (muted at bottom in-app)
- Generate app and release artifacts:

```bash
python3 scripts/generate_changelog.py
```

- Generated per-version release bodies for GitHub are written to:
  - `changelog/generated/releases/<version>.md`
  - `changelog/generated/releases/<version>.txt`
- On `stable`, GitHub Actions compares the latest changelog version to the latest `v*` tag:
  - If the changelog version is newer, CI creates that immutable versioned release
  - If not, CI updates the rolling `stable-latest` release instead

- Validate generated output is up to date (CI-friendly):

```bash
python3 scripts/generate_changelog.py --check
```

## Configuration Files

| File | Purpose |
|------|---------|
| `flake.nix` | Nix development environment |
| `pubspec.yaml` | Flutter dependencies |
| `analysis_options.yaml` | Linter rules |
| `lib/firebase_options.dart` | Firebase configuration |
| `.github/workflows/ci.yml` | CI/CD pipeline |

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run tests: `flutter test`
5. Format code: `dart format lib test`
6. Commit: `git commit -m 'Add my feature'`
7. Push: `git push origin feature/my-feature`
8. Create a Pull Request

## Code Style

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart)
- Use trailing commas for better diffs
- Document public APIs with `///` comments
- Keep functions focused and under 50 lines when possible

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Flutter](https://flutter.dev) - UI framework
- [Firebase](https://firebase.google.com) - Backend services
- [Provider](https://pub.dev/packages/provider) - State management
- [Flutter Quill](https://pub.dev/packages/flutter_quill) - Rich text editor
