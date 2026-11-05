// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlimpseCore",
    platforms: [.macOS(.v12)],
    products: [.library(name: "GlimpseCore", targets: ["GlimpseCore"])],
    targets: [.target(name: "GlimpseCore", path: "GlimpseCore/Sources")]
)
