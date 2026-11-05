import XCTest
@testable import GlimpseCore

final class FileNavigatorTests: XCTestCase {
    func testNaturalSortAndWrappingInBothDirections() throws {
        let folder = try TemporaryFolder()
        let first = try folder.file("img2.jpg")
        let second = try folder.file("img10.JPG")
        var navigator = FileNavigator(currentURL: first)
        XCTAssertEqual(navigator.totalCount, 2)
        navigator.moveToNext()
        XCTAssertEqual(navigator.currentURL, second)
        navigator.moveToNext()
        XCTAssertEqual(navigator.currentURL, first)
        navigator.moveToPrevious()
        XCTAssertEqual(navigator.currentURL, second)
    }

    func testDirectoriesWithImageExtensionsAndHiddenSiblingsAreExcluded() throws {
        let folder = try TemporaryFolder()
        let first = try folder.file("photo.jpg")
        try folder.file(".hidden.jpg")
        try folder.file("notes.txt")
        try FileManager.default.createDirectory(at: folder.url.appendingPathComponent("fake.png"), withIntermediateDirectories: false)
        XCTAssertEqual(FileNavigator(currentURL: first).totalCount, 1)
    }

    func testExplicitlyOpenedHiddenFileKeepsItsOwnPosition() throws {
        let folder = try TemporaryFolder()
        let hidden = try folder.file(".hidden.jpg")
        let visible = try folder.file("visible.jpg")
        var navigator = FileNavigator(currentURL: hidden)
        XCTAssertEqual(navigator.totalCount, 2)
        navigator.moveToNext()
        XCTAssertEqual(navigator.currentURL, visible)
        navigator.moveToPrevious()
        XCTAssertEqual(navigator.currentURL, hidden)
    }

    func testUnsupportedExtensionCanStillBeNavigatedWhenExplicitlyOpened() throws {
        let folder = try TemporaryFolder()
        let first = try folder.file("original.custom")
        var navigator = FileNavigator(currentURL: first)
        XCTAssertEqual(navigator.totalCount, 1)
        navigator.moveToNext()
        XCTAssertEqual(navigator.currentURL, first)
    }

    func testMissingDirectoryFallsBackToTheSelectedFile() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/image.jpg")
        var navigator = FileNavigator(currentURL: url)
        navigator.moveToPrevious()
        XCTAssertEqual(navigator.currentURL, url)
        XCTAssertEqual(navigator.totalCount, 1)
    }

    func testSymlinkedDirectoryDoesNotDuplicateTheCurrentImage() throws {
        let folder = try TemporaryFolder()
        let realDirectory = folder.url.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: false)
        let alias = folder.url.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: realDirectory)
        try Data().write(to: realDirectory.appendingPathComponent("photo.jpg"))
        let navigator = FileNavigator(currentURL: alias.appendingPathComponent("photo.jpg"))
        XCTAssertEqual(navigator.totalCount, 1)
        XCTAssertEqual(navigator.currentURL, realDirectory.appendingPathComponent("photo.jpg"))
    }
}
