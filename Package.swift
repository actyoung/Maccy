// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MaccyLocalPrivacy",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Maccy", targets: ["Maccy"])
  ],
  dependencies: [
    .package(path: ".swiftpm-local/dependencies/defaults"),
    .package(path: ".swiftpm-local/dependencies/fuse-swift"),
    .package(path: ".swiftpm-local/dependencies/keyboardshortcuts"),
    .package(path: ".swiftpm-local/dependencies/launchatlogin-modern"),
    .package(path: ".swiftpm-local/dependencies/sauce"),
    .package(path: ".swiftpm-local/dependencies/settings"),
    .package(path: ".swiftpm-local/dependencies/swift-log"),
    .package(path: ".swiftpm-local/dependencies/swifthexcolors")
  ],
  targets: [
    .executableTarget(
      name: "Maccy",
      dependencies: [
        .product(name: "Defaults", package: "defaults"),
        .product(name: "Fuse", package: "fuse-swift"),
        .product(name: "KeyboardShortcuts", package: "keyboardshortcuts"),
        .product(name: "LaunchAtLogin", package: "launchatlogin-modern"),
        .product(name: "Sauce", package: "sauce"),
        .product(name: "Settings", package: "settings"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "SwiftHEXColors", package: "swifthexcolors")
      ],
      path: "Maccy",
      exclude: [
        "AppIcon.icon",
        "AppStoreReview.swift",
        "Assets.xcassets",
        "GlobalHotKey.swift",
        "History.xcdatamodeld",
        "Info.plist",
        "Intents",
        "Maccy.entitlements",
        "SoftwareUpdater.swift",
        "Sounds",
        "Storage.xcdatamodeld"
      ]
    )
  ],
  swiftLanguageModes: [.v5]
)
