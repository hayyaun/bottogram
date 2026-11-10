# macOS test builds

The macOS build targets macOS 13 or later and produces a universal app for Apple
Silicon and Intel. CI runs the native integration tests on both architectures.
The download is an ad hoc signed test build, without Developer ID signing or
notarization; it is not a completed public distribution setup.

## Secret storage and App Sandbox

`PlatformSecretVault` configures the supported
`MacOsOptions(usesDataProtectionKeychain: false)` option. On macOS, this uses the
file-based Keychain through the standard SecItem API. In a normal user session,
new items go to the user's default Keychain, ordinarily the login Keychain.
Other platforms keep their existing storage options.

This mode does not require Keychain Sharing, a provisioning profile or the
restricted `keychain-access-groups` entitlement. App Sandbox stays enabled;
network access and access to user-selected files retain their normal
entitlements. Debug builds also retain their Flutter JIT and debug connection
permissions.

File-based Keychain access uses access control lists tied to the app's code
identity. macOS may ask for access or to unlock the Keychain. Ad hoc signing
does not establish a stable developer identity across rebuilt apps, so a passing
same-build test does not guarantee prompt-free access after an update.

Apple recommends the newer Data Protection Keychain. The file-based
implementation remains supported but has API shim limitations and is moving
toward deprecation. Selecting this mode does not read, copy or migrate secrets
previously stored in the Data Protection Keychain.

## Native storage verification

On a configured Mac, run:

```sh
flutter test integration_test/secret_vault_test.dart -d macos --no-pub --reporter expanded
```

The test uses the real `PlatformSecretVault` and one cryptographically random
disposable key. It checks absence, write/read, replacement/read, deletion/read
and repeated deletion, then cleans up only that key. It does not launch the
normal application, open Hive, enumerate credentials or use saved bot data.
It checks same-build storage operations, not persistence across signed app
updates, notarization or clean-machine distribution.

## Moving to provisioned Data Protection storage

For that path, configure an Apple signing identity and a provisioning profile
that authorizes the app's Keychain access group, restore the corresponding
entitlement in both DebugProfile and Release, and use the default
`MacOsOptions(usesDataProtectionKeychain: true)`. Keep App Sandbox enabled and
verify the signed app's actual entitlements, native storage operations and
distribution behavior. Public distribution also needs its appropriate Developer
ID signing and notarization setup.

The two Keychain implementations are separate stores. Review any existing-data
transition separately before adding migration code; changing the option alone
does not move secrets. Plan verification and recovery before switching an app
that already holds credentials.

References:

- [Package configuration and the no-sharing option](https://pub.dev/packages/flutter_secure_storage_darwin#macos-keychain-sharing-requires-provisioning)
- [Apple TN3137: Mac Keychain implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)
- [Apple TN3125: Provisioning and restricted entitlements](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- [Apple: Keychain access and code identity](https://developer.apple.com/forums/thread/115425)
