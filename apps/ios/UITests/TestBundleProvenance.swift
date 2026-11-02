import XCTest
import CryptoKit

func recordTestBundleProvenance(_ testClass: AnyClass) {
    guard let url = Bundle(for: testClass).executableURL,
          let data = try? Data(contentsOf: url) else {
        XCTFail("Cannot verify the actual loaded test bundle")
        return
    }
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    print("MILO_LOADED_TEST_BUNDLE_SHA256=" + hash)
}
