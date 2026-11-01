// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacPanel",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacPanel", targets: ["MacPanel"])],
    targets: [.executableTarget(name: "MacPanel", path: "Sources/MacPanel")]
)
