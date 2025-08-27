import Foundation
import MMKV
import RealmSwift
import os

class ChatSharedDataManager {
    private let logger = Logger(
        subsystem: "NotificationExtension",
        category: "ChatSharedDataManager"
    )
    
    static let shared = ChatSharedDataManager()
    private init() {}
    
    // MARK: - No Caching, No State - Each Call is Independent
    
    private var mmkvInitialized = false
    private let initLock = NSLock()
    
    /// Initialize MMKV once per extension process
    private func ensureMMKVInitialized(groupDirPath: String) {
        initLock.lock()
        defer { initLock.unlock() }
        
        if !mmkvInitialized {
            MMKV.initialize(rootDir: nil, groupDir: groupDirPath, logLevel: .info)
            mmkvInitialized = true
        }
    }
    
    // MARK: - Core Functions (No State, No Caching)
    
    func getJWTToken(hostAppBundleId: String) -> String? {
        guard let containerURL = getContainerURL(hostAppBundleId: hostAppBundleId) else {
            logger.error("Container not found for bundle: \(hostAppBundleId)")
            return nil
        }
        
        ensureMMKVInitialized(groupDirPath: containerURL.path)
        
        guard let mmkv = MMKV(mmapID: "default", mode: .multiProcess) else {
            logger.error("Failed to create MMKV instance")
            return nil
        }
        
        return mmkv.string(forKey: "Token")
    }
    
    func getContact(byUsername username: String, hostAppBundleId: String) -> ContactV3? {
        guard let realm = getRealm(hostAppBundleId: hostAppBundleId) else {
            return nil
        }
        
        return realm.objects(ContactV3.self)
            .filter("username == %@", username)
            .first
    }
    
    func getContacts(byUserIds userIds: [String], hostAppBundleId: String) -> [ContactV3] {
        guard !userIds.isEmpty else { return [] }
        
        guard let realm = getRealm(hostAppBundleId: hostAppBundleId) else {
            return []
        }
        
        return Array(realm.objects(ContactV3.self).filter("userId IN %@", userIds))
    }
    
    func buildImageURL(
        groupType: String,
        groupId: String,
        userId: String,
        hostAppBundleId: String
    ) -> String? {
        guard let apiURL = getAPIURL(),
              let token = getJWTToken(hostAppBundleId: hostAppBundleId) else {
            return nil
        }
        
        let path = (groupType == "PRIVATE_GROUP")
            ? "groups/\(groupId)/picture"
            : "users/\(userId)/profile-picture"
        
        return "\(apiURL)\(path)?token=\(token)"
    }
    
    func decodeJWT(hostAppBundleId: String) -> [String: Any]? {
        guard let token = getJWTToken(hostAppBundleId: hostAppBundleId) else {
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
    
    func sendMessageAcknowledgement(
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
    
    func sendRejectCall(
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
            schemaVersion: 205,
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
        guard let apiURL = getAPIURL(),
              let token = getJWTToken(hostAppBundleId: hostAppBundleId),
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
}

// MARK: - Models

struct Mention: Codable {
    let id: String
    let name: String
    let startPosition: Int
    let endPosition: Int
}

class ContactV3: Object {
    @Persisted(primaryKey: true) var username: String = ""
    @Persisted var name: String = ""
    @Persisted var userId: String?
    
    override init() {
        super.init()
    }
}
