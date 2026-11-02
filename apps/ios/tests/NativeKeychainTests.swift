import XCTest
import CryptoKit
@testable import Milo

/// Exercises the system Keychain in the signed host application. All services
/// derive from random temporary directories; every key is synthetic and scoped.
@MainActor final class NativeKeychainTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let executable = try XCTUnwrap(Bundle(for: Self.self).executableURL)
        let digest = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
        print("MILO_LOADED_TEST_BUNDLE_SHA256=" + digest)
    }

    private func directory() throws -> URL {
        let result = FileManager.default.temporaryDirectory
            .appendingPathComponent("MILO-NativeKeychainTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    func testRealKeychainRoundTripUpdateIsolationAndDeletion() throws {
        let first = try directory(), second = try directory()
        let keychain = AccountKeychain(directory: first), otherStore = AccountKeychain(directory: second)
        let uid = UUID().uuidString, otherUID = UUID().uuidString
        let destination = "https://" + UUID().uuidString.lowercased() + ".invalid/v1"
        let otherDestination = "https://" + UUID().uuidString.lowercased() + ".invalid/v1"
        let firstKey = "synthetic-test-" + UUID().uuidString
        let replacement = "synthetic-replacement-" + UUID().uuidString
        defer {
            for store in [keychain, otherStore] {
                for id in [uid, otherUID] {
                    do { try store.delete(uid: id) }
                    catch { XCTFail("Synthetic Keychain cleanup failed: \(error)") }
                }
            }
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        XCTAssertNil(try keychain.read(uid: uid, destination: destination))
        try keychain.save(firstKey, uid: uid, destination: destination)
        XCTAssertEqual(try keychain.read(uid: uid, destination: destination), firstKey)
        XCTAssertNil(try keychain.read(uid: otherUID, destination: destination))
        XCTAssertNil(try keychain.read(uid: uid, destination: otherDestination))
        XCTAssertNil(try otherStore.read(uid: uid, destination: destination))
        try keychain.save(replacement, uid: uid, destination: destination)
        XCTAssertEqual(try keychain.read(uid: uid, destination: destination), replacement)

        try keychain.save("synthetic-other-uid", uid: otherUID, destination: destination)
        try keychain.save("synthetic-other-destination", uid: uid, destination: otherDestination)
        try otherStore.save("synthetic-other-store", uid: uid, destination: destination)
        try keychain.delete(uid: uid, destination: destination)
        XCTAssertNil(try keychain.read(uid: uid, destination: destination))
        XCTAssertEqual(try keychain.read(uid: otherUID, destination: destination), "synthetic-other-uid")
        XCTAssertEqual(try keychain.read(uid: uid, destination: otherDestination), "synthetic-other-destination")
        XCTAssertEqual(try otherStore.read(uid: uid, destination: destination), "synthetic-other-store")
        try keychain.delete(uid: uid)
        XCTAssertNil(try keychain.read(uid: uid, destination: otherDestination))
        XCTAssertEqual(try keychain.read(uid: otherUID, destination: destination), "synthetic-other-uid")
    }

    func testLocalAccountDeletionCleansRealKeychainAndSyntheticFiles() async throws {
        let directory = try directory()
        // Explicitly prevent the factory from initializing any configured remote
        // service. Local owner deletion never contacts an email/account server.
        let model = AccountModel(directory: directory, authProvider: UnconfiguredAGCAuthProvider())
        let store = AccountKeychain(directory: directory)
        let otherUID = UUID().uuidString
        let destination = "https://" + UUID().uuidString.lowercased() + ".invalid/v1"
        let secondDestination = destination + "/other"
        var ownedUID: String?
        defer {
            for uid in [ownedUID, otherUID].compactMap({ $0 }) {
                do { try store.delete(uid: uid) }
                catch { XCTFail("Synthetic Keychain cleanup failed: \(error)") }
            }
            try? FileManager.default.removeItem(at: directory)
        }
        XCTAssertTrue(model.signInLocally())
        let uid = try XCTUnwrap(model.identity?.uid); ownedUID = uid
        try store.save("synthetic-owner-key-" + UUID().uuidString, uid: uid, destination: destination)
        try store.save("synthetic-owner-second", uid: uid, destination: secondDestination)
        try store.save("synthetic-other-uid", uid: otherUID, destination: destination)
        let memoryFile = directory.appendingPathComponent("journal.json")
        try Data("synthetic-memory".utf8).write(to: memoryFile)
        var cleanupCalled = false
        let deleted = await model.deleteAccount {
            cleanupCalled = true
            do { try FileManager.default.removeItem(at: memoryFile); return true }
            catch { return false }
        }
        XCTAssertTrue(deleted, model.errorMessage)
        XCTAssertTrue(cleanupCalled)
        XCTAssertNil(model.identity)
        XCTAssertFalse(FileManager.default.fileExists(atPath: memoryFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("account.json").path))
        XCTAssertNil(try store.read(uid: uid, destination: destination))
        XCTAssertNil(try store.read(uid: uid, destination: secondDestination))
        XCTAssertEqual(try store.read(uid: otherUID, destination: destination), "synthetic-other-uid")
        let restored = AccountModel(directory: directory, authProvider: UnconfiguredAGCAuthProvider())
        XCTAssertFalse(restored.isAuthenticated)
    }
}
