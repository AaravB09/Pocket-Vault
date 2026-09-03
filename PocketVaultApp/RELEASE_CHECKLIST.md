# Release Checklist

## Android — before every Play Store upload

- [ ] Open Sources/PocketVault/Entitlementmanager.swift
- [ ] Find: private let androidDevBuildsOnly: Bool = true
- [ ] Change true to false
- [ ] Run this from PocketVaultApp/ in Terminal — it must print NOTHING:
      grep -n "androidDevBuildsOnly = true" Sources/PocketVault/Entitlementmanager.swift
- [ ] Build the release APK/AAB
- [ ] Commit the flip by itself: git commit -m "Release: disable Android dev Pro override"
- [ ] AFTER release ships, if going back to testing: flip back to true, commit again

## iOS — before every App Store / TestFlight release

- [ ] Nothing to do — #if DEBUG is stripped automatically in Release builds.