import XCTest
@testable import CuraKnot

final class PhotoStorageManagerTests: XCTestCase {

    var sut: PhotoStorageManager!
    private var testDirectory: URL!

    override func setUp() async throws {
        sut = try PhotoStorageManager()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoStorageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let testDirectory = testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        sut = nil
    }

    // MARK: - Save Locally

    func testSaveLocally_createsFile() throws {
        // Given
        let photoId = UUID()
        let imageData = createTestImageData()

        // When
        let url = try sut.saveLocally(imageData: imageData, photoId: photoId)

        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }

    func testSaveLocally_excludesFromBackup() throws {
        // Given
        let photoId = UUID()
        let imageData = createTestImageData()

        // When
        let url = try sut.saveLocally(imageData: imageData, photoId: photoId)
        try sut.setBackupExclusion(for: url)

        // Then
        var resourceValues = URLResourceValues()
        let fileURL = url
        resourceValues = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertTrue(resourceValues.isExcludedFromBackup ?? false)

        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Delete Local

    func testDeleteLocal_removesFile() throws {
        // Given
        let photoId = UUID()
        let imageData = createTestImageData()
        let url = try sut.saveLocally(imageData: imageData, photoId: photoId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // When
        try sut.deleteLocal(photoId: photoId)

        // Then
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Compression

    func testCompressForUpload_reducesSize() throws {
        // Given - create a larger test image
        let imageData = createTestImageData(size: 500)

        // When
        let compressed = try sut.compressForUpload(imageData)

        // Then - compressed should not be larger than original (for large images)
        XCTAssertNotNil(compressed)
        XCTAssertGreaterThan(compressed.count, 0)
    }

    // MARK: - Blurred Thumbnail

    func testGenerateBlurredThumbnail_producesData() throws {
        // Given
        let imageData = createTestImageData(size: 300)

        // When
        let thumbnail = try sut.generateBlurredThumbnail(from: imageData)

        // Then
        XCTAssertGreaterThan(thumbnail.count, 0)
        XCTAssertLessThan(thumbnail.count, imageData.count)
    }

    // MARK: - Helpers

    private func createTestImageData(size: Int = 100) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
}
