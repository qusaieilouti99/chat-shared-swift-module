import Foundation
import MMKV
import RealmSwift
import os

public class ChatSharedDataManager {
    private let logger = Logger(
        subsystem: "ChatSharedDataManager",
        category: "ChatSharedDataManager"
    )

    public static let shared = ChatSharedDataManager()
    private init() {}

    // MARK: - Thread-safe MMKV initialization tracking
    private var mmkvInitializedPaths = Set<String>()
    private let initLock = NSLock()

    /// Initialize MMKV once per group directory path (doesn't interfere with react-native-mmkv)
    private func ensureMMKVInitialized(groupDirPath: String) {
        initLock.lock()
        defer { initLock.unlock() }

        if !mmkvInitializedPaths.contains(groupDirPath) {
            MMKV.initialize(rootDir: nil, groupDir: groupDirPath, logLevel: .info)
            mmkvInitializedPaths.insert(groupDirPath)
        }
    }

    // MARK: - Core Functions (Resource-Safe, Instance-Specific Cleanup)

    public func getJWTToken(hostAppBundleId: String) -> String? {
        var mmkvInstance: MMKV?

        defer {
            // Only cleanup the instance we created
            cleanupMMKVInstance(mmkvInstance)
        }

        guard let containerURL = getContainerURL(hostAppBundleId: hostAppBundleId) else {
            logger.error("Container not found for bundle: \(hostAppBundleId)")
            return nil
        }

        ensureMMKVInitialized(groupDirPath: containerURL.path)

        guard let mmkv = MMKV(mmapID: "default", mode: .multiProcess) else {
            logger.error("Failed to create MMKV instance")
            return nil
        }

        mmkvInstance = mmkv
        return mmkv.string(forKey: "Token")
    }

    public func getContact(byUsername username: String, hostAppBundleId: String) -> ContactV3? {
        var realmInstance: Realm?
        var result: ContactV3?

        defer {
            // Only cleanup the realm instance we created
            cleanupRealmInstance(realmInstance)
        }

        autoreleasepool {
            guard let realm = getRealm(hostAppBundleId: hostAppBundleId) else {
                return
            }

            realmInstance = realm

            // Create a detached copy to avoid Realm threading issues
            if let contact = realm.objects(ContactV3.self).filter("username == %@", username).first {
                result = ContactV3()
                result?.username = contact.username
                result?.name = contact.name
                result?.userId = contact.userId
            }
        }

        return result
    }

    public func getContacts(byUserIds userIds: [String], hostAppBundleId: String) -> [ContactV3] {
        guard !userIds.isEmpty else { return [] }

        var realmInstance: Realm?
        var results: [ContactV3] = []

        defer {
            // Only cleanup the realm instance we created
            cleanupRealmInstance(realmInstance)
        }

        autoreleasepool {
            guard let realm = getRealm(hostAppBundleId: hostAppBundleId) else {
                return
            }

            realmInstance = realm
            let contacts = realm.objects(ContactV3.self).filter("userId IN %@", userIds)

            // Create detached copies
            for contact in contacts {
                let detachedContact = ContactV3()
                detachedContact.username = contact.username
                detachedContact.name = contact.name
                detachedContact.userId = contact.userId
                results.append(detachedContact)
            }
        }

        return results
    }

    public func buildImageURL(
        groupType: String,
        groupId: String,
        userId: String,
        hostAppBundleId: String
    ) -> String? {
        var mmkvInstance: MMKV?

        defer {
            // Only cleanup the instance we created
            cleanupMMKVInstance(mmkvInstance)
        }

        guard let apiURL = getAPIURL() else {
            return nil
        }

        // Get token using our internal method to reuse MMKV instance
        guard let containerURL = getContainerURL(hostAppBundleId: hostAppBundleId) else {
            logger.error("Container not found for bundle: \(hostAppBundleId)")
            return nil
        }

        ensureMMKVInitialized(groupDirPath: containerURL.path)

        guard let mmkv = MMKV(mmapID: "default", mode: .multiProcess) else {
            logger.error("Failed to create MMKV instance")
            return nil
        }

        mmkvInstance = mmkv

        guard let token = mmkv.string(forKey: "Token") else {
            return nil
        }

        let path = (groupType == "PRIVATE_GROUP")
            ? "groups/\(groupId)/picture"
            : "users/\(userId)/profile-picture"

        return "\(apiURL)\(path)?token=\(token)"
    }

    public func decodeJWT(hostAppBundleId: String) -> [String: Any]? {
        var mmkvInstance: MMKV?

        defer {
            // Only cleanup the instance we created
            cleanupMMKVInstance(mmkvInstance)
        }

        guard let containerURL = getContainerURL(hostAppBundleId: hostAppBundleId) else {
            logger.error("Container not found for bundle: \(hostAppBundleId)")
            return nil
        }

        ensureMMKVInitialized(groupDirPath: containerURL.path)

        guard let mmkv = MMKV(mmapID: "default", mode: .multiProcess) else {
            logger.error("Failed to create MMKV instance")
            return nil
        }

        mmkvInstance = mmkv

        guard let token = mmkv.string(forKey: "Token") else {
            return nil
        }

        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        let payloadSegment = String(segments[1])
        var base64 = payloadSegment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padLen = 4 - base64.count % 4
        if padLen < 4 {
            base64.append(String(repeating: "=", count: padLen))
        }

        guard let data = Data(base64Encoded: base64) else { return nil }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - API Calls

    public func sendMessageAcknowledgement(
        messageId: String,
        userId: String,
        hostAppBundleId: String,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        makeAPICall(
            endpoint: "whisper-messages/\(messageId)/received",
            parameters: ["userId": userId],
            hostAppBundleId: hostAppBundleId,
            completion: completion
        )
    }

    public func sendRejectCall(
        callId: String,
        hostAppBundleId: String,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        makeAPICall(
            endpoint: "calls/reject",
            parameters: ["callId": callId],
            hostAppBundleId: hostAppBundleId,
            completion: completion
        )
    }

    // MARK: - Private Helpers

    private func getContainerURL(hostAppBundleId: String) -> URL? {
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.\(hostAppBundleId)"
        )
    }

    private func getRealm(hostAppBundleId: String) -> Realm? {
        guard let containerURL = getContainerURL(hostAppBundleId: hostAppBundleId) else {
            logger.error("Container not found")
            return nil
        }

        let realmURL = containerURL.appendingPathComponent("default.realm")
        let config = Realm.Configuration(
            fileURL: realmURL,
            readOnly: true,
            schemaVersion: 206,
            objectTypes: [ContactV3.self]
        )

        do {
            return try Realm(configuration: config)
        } catch {
            logger.error("Realm initialization failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func getAPIURL() -> String? {
        return Bundle.main.infoDictionary?["API_URL"] as? String
    }

    private func makeAPICall(
        endpoint: String,
        parameters: [String: Any],
        hostAppBundleId: String,
        completion: @escaping (Bool) -> Void
    ) {
        var mmkvInstance: MMKV?

        defer {
            // Cleanup after API call
            cleanupMMKVInstance(mmkvInstance)
        }

        guard let apiURL = getAPIURL() else {
            completion(false)
            return
        }

        // Get token using our own MMKV instance
        guard let containerURL = getContainerURL(hostAppBundleId: hostAppBundleId) else {
            logger.error("Container not found for bundle: \(hostAppBundleId)")
            completion(false)
            return
        }

        ensureMMKVInitialized(groupDirPath: containerURL.path)

        guard let mmkv = MMKV(mmapID: "default", mode: .multiProcess) else {
            logger.error("Failed to create MMKV instance")
            completion(false)
            return
        }

        mmkvInstance = mmkv

        guard let token = mmkv.string(forKey: "Token"),
              let url = URL(string: "\(apiURL)\(endpoint)") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch {
            logger.error("JSON serialization failed: \(error.localizedDescription)")
            completion(false)
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            let success = error == nil &&
                (response as? HTTPURLResponse)?.statusCode ?? 0 >= 200 &&
                (response as? HTTPURLResponse)?.statusCode ?? 0 < 300
            completion(success)
        }.resume()
    }

    // MARK: - Instance-Specific Cleanup (Won't interfere with react-native-mmkv)

    /// Clean up only the specific MMKV instance we created
    private func cleanupMMKVInstance(_ mmkv: MMKV?) {
        guard let mmkv = mmkv else { return }

        // Only clear memory cache for this specific instance
        // This won't affect other MMKV instances like react-native-mmkv
        mmkv.clearMemoryCache()

        // Force release in autoreleasepool
        autoreleasepool { }
    }

    /// Clean up only the specific Realm instance we created
    private func cleanupRealmInstance(_ realm: Realm?) {
        guard let realm = realm else { return }

        // Only invalidate this specific realm instance
        realm.invalidate()

        // Force release in autoreleasepool
        autoreleasepool { }
    }
}

// MARK: - Models

public struct Mention: Codable {
    public let id: String
    public let name: String
    public let startPosition: Int
    public let endPosition: Int

    public init(id: String, name: String, startPosition: Int, endPosition: Int) {
        self.id = id
        self.name = name
        self.startPosition = startPosition
        self.endPosition = endPosition
    }
}

public class ContactV3: Object {
    @Persisted(primaryKey: true) public var username: String = ""
    @Persisted public var name: String = ""
    @Persisted public var userId: String?

    public override init() {
        super.init()
    }
}