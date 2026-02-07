// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CuraKnot",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "CuraKnot",
            targets: ["CuraKnot"]
        ),
    ],
    dependencies: [
        // GRDB for local SQLite persistence (with SQLCipher encryption support via prepareDatabase)
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        // Supabase Swift SDK for auth, database, functions, storage
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "CuraKnot",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: "CuraKnot"
        ),
        .testTarget(
            name: "CuraKnotTests",
            dependencies: ["CuraKnot"],
            path: "CuraKnotTests"
        ),
    ]
)
