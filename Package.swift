// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RF4",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "rf4", targets: ["RF4CLI"])
  ],
  targets: [
    .target(name: "RF4Core"),
    .executableTarget(
      name: "RF4CLI",
      dependencies: ["RF4Core"],
      linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("IOUSBHost")]
    ),
    .testTarget(
      name: "RF4CoreTests",
      dependencies: ["RF4Core"],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(name: "RF4CLITests", dependencies: ["RF4CLI", "RF4Core"]),
  ]
)
