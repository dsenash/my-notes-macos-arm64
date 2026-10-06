import Foundation
import Network
import CryptoKit
import CommonCrypto
import Security

// MARK: - Константы и ошибки

enum SyncConst {
    static let app = "MyNotes"
    static let proto = 1
    static let defaultPort = 7443
    static let chunkSize = 256 * 1024
    static let maxControlFrame = 16 * 1024
    static let maxPackageBytes: Int64 = 1_500_000_000
}

enum SyncError: LocalizedError {
    case timeout, cancelled, connectionClosed, protocolViolation
    case denied, busy, wrongPassphrase, passphraseMismatch, integrity, tooLarge, badPort
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .timeout: return "Превышено время ожидания ответа."
        case .cancelled: return "Синхронизация отменена."
        case .connectionClosed: return "Соединение было закрыто."
        case .protocolViolation: return "Устройство ответило неожиданным образом (возможно, другая версия MyNotes)."
        case .denied: return "Запрос отклонён на другом устройстве."
        case .busy: return "Другое устройство сейчас занято другой синхронизацией. Повторите позже."
        case .wrongPassphrase: return "Пароль синхронизации не совпадает с паролем на другом устройстве."
        case .passphraseMismatch: return "Пароль синхронизации должен быть задан (или не задан) одинаково на обоих устройствах."
        case .integrity: return "Данные повреждены при передаче (не совпала контрольная сумма)."
        case .tooLarge: return "Пакет данных слишком большой."
        case .badPort: return "Некорректный порт."
        case .remote(let text): return "Другое устройство сообщило об ошибке: \(text)"
        }
    }
}

extension Error {
    /// Пользователь сам нажал «Отмена» — отдельное окно с ошибкой не нужно.
    var isUserCancel: Bool {
        if let error = self as? SyncError, case .cancelled = error { return true }
        return false
    }
}

// MARK: - Сообщения протокола

/// Кадр: [4 байта длины (тип + тело), big-endian][1 байт типа][тело].
enum FrameType: UInt8 {
    case hello = 0     // проверка «это MyNotes?» при сканировании
    case request = 1   // запрос синхронизации с именем компьютера
    case reply = 2     // ответ: принято / отклонено / занято + заголовок пакета
    case chunk = 3     // кусок пакета: [4 байта номера][данные или шифртекст]
    case ack = 4       // получатель подтверждает успешный приём
    case error = 5     // сообщение об ошибке
}

struct HelloMessage: Codable {
    var app: String
    var proto: Int
    var deviceName: String
    var deviceID: String
}

struct RequestMessage: Codable {
    var app: String
    var proto: Int
    var deviceName: String
    var deviceID: String
}

struct ReplyMessage: Codable {
    var status: String            // "accepted" | "denied" | "busy"
    var deviceName: String
    var totalBytes: Int64 = 0
    var chunkSize: Int = 0
    var sha256: String = ""
    var encrypted: Bool = false
    var salt: String = ""         // base64, соль для PBKDF2
    var check: String = ""        // base64, зашифрованная константа для проверки пароля
    var projects: Int = 0
    var notes: Int = 0
}

struct ErrorMessage: Codable {
    var message: String
}

// MARK: - Идентификация устройства

enum SyncIdentity {
    static let deviceName: String = {
        sanitize(Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
    }()

    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "sync.deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "sync.deviceID")
        return id
    }

    /// Имя пришло по сети и недоверенное: убираем управляющие символы, переводы строк и
    /// символы смены направления текста, ограничиваем длину.
    static func sanitize(_ text: String) -> String {
        let bidi = CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}\u{200E}\u{200F}")
        let bad = CharacterSet.controlCharacters.union(.newlines).union(bidi)
        let characters = text.unicodeScalars.filter { !bad.contains($0) }.map { Character($0) }
        let cleaned = String(characters.prefix(64)).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Неизвестное устройство" : cleaned
    }
}

// MARK: - Пароль синхронизации (Keychain)

enum SyncSecrets {
    private static let service = "com.mynotes.app.sync"
    private static let account = "passphrase"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static var passphrase: String {
        get {
            var query = baseQuery()
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        set {
            SecItemDelete(baseQuery() as CFDictionary)
            guard !newValue.isEmpty else { return }
            var query = baseQuery()
            query[kSecValueData as String] = Data(newValue.utf8)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }
}

// MARK: - Шифрование (необязательное): PBKDF2 → AES-256-GCM по каждому куску

enum SyncCrypto {
    static let checkPlain = Data("MyNotes-sync-v1".utf8)
    private static let checkAAD = Data("check".utf8)

    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return data
    }

    static func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        let password = Array(passphrase.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let saltBytes = [UInt8](salt)
        _ = password.withUnsafeBufferPointer { pw in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                UnsafeRawPointer(pw.baseAddress!).assumingMemoryBound(to: Int8.self), password.count,
                saltBytes, saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                200_000,
                &derived, derived.count
            )
        }
        return SymmetricKey(data: derived)
    }

    static func chunkAAD(index: UInt32, total: UInt32) -> Data {
        bigEndian(index) + bigEndian(total)
    }

    static func seal(_ plain: Data, key: SymmetricKey, aad: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key, authenticating: aad).combined else {
            throw SyncError.protocolViolation
        }
        return combined
    }

    static func open(_ sealed: Data, key: SymmetricKey, aad: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw SyncError.wrongPassphrase
        }
    }

    static func makeCheck(key: SymmetricKey) throws -> String {
        try seal(checkPlain, key: key, aad: checkAAD).base64EncodedString()
    }

    static func verifyCheck(_ base64: String, key: SymmetricKey) -> Bool {
        guard let sealed = Data(base64Encoded: base64),
              let plain = try? open(sealed, key: key, aad: checkAAD) else { return false }
        return plain == checkPlain
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

func bigEndian(_ value: UInt32) -> Data {
    Data([UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
}

func readBigEndian(_ data: Data) -> UInt32 {
    data.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
}

// MARK: - Кадровое соединение поверх NWConnection

final class FramedConnection {
    let conn: NWConnection
    let queue: DispatchQueue

    private let lock = NSLock()
    private var timeoutItem: DispatchWorkItem?
    private var timedOut = false
    private var userCancelled = false

    init(_ conn: NWConnection, queue: DispatchQueue) {
        self.conn = conn
        self.queue = queue
    }

    func start() {
        conn.start(queue: queue)
    }

    // MARK: Отправка и приём кадров (колбэки)

    func send(_ type: FrameType, _ body: Data, completion: @escaping (NWError?) -> Void) {
        var frame = bigEndian(UInt32(body.count + 1))
        frame.append(type.rawValue)
        frame.append(body)
        conn.send(content: frame, completion: .contentProcessed(completion))
    }

    func receiveFrame(maxLength: Int, _ handler: @escaping (Result<(FrameType, Data), Error>) -> Void) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, _, error in
            guard let self else { return }
            if let error { handler(.failure(error)); return }
            guard let header, header.count == 4 else { handler(.failure(SyncError.connectionClosed)); return }
            let length = Int(readBigEndian(header))
            guard length >= 1, length <= maxLength else { handler(.failure(SyncError.protocolViolation)); return }
            self.conn.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                if let error { handler(.failure(error)); return }
                guard let body, body.count == length, let first = body.first,
                      let type = FrameType(rawValue: first) else {
                    handler(.failure(SyncError.protocolViolation))
                    return
                }
                handler(.success((type, Data(body.dropFirst()))))
            }
        }
    }

    // MARK: Async-обёртки

    func sendAsync(_ type: FrameType, _ body: Data = Data()) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            send(type, body) { error in
                if let error { cont.resume(throwing: self.mapError(error)) } else { cont.resume() }
            }
        }
    }

    func sendJSONAsync<T: Encodable>(_ type: FrameType, _ value: T) async throws {
        try await sendAsync(type, try JSONEncoder().encode(value))
    }

    func receiveAsync(maxLength: Int) async throws -> (FrameType, Data) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(FrameType, Data), Error>) in
            receiveFrame(maxLength: maxLength) { result in
                switch result {
                case .success(let frame): cont.resume(returning: frame)
                case .failure(let error): cont.resume(throwing: self.mapError(error))
                }
            }
        }
    }

    static func connect(host: String, port: UInt16, timeout: TimeInterval) async throws -> FramedConnection {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw SyncError.badPort }
        let queue = DispatchQueue(label: "mynotes.sync.client")
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let framed = FramedConnection(conn, queue: queue)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var finished = false   // меняется только на queue
            let finish: (Error?) -> Void = { error in
                guard !finished else { return }
                finished = true
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(nil)
                case .failed(let error): finish(error)
                case .waiting(let error): finish(error)
                case .cancelled: finish(SyncError.connectionClosed)
                default: break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                if !finished {
                    finish(SyncError.timeout)
                    conn.cancel()
                }
            }
        }
        return framed
    }

    // MARK: Тайм-ауты и отмена

    /// Через `seconds` секунд без вызова `disarmTimeout()` / повторного `armTimeout` соединение закрывается.
    func armTimeout(_ seconds: TimeInterval) {
        lock.lock()
        timeoutItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.timedOut = true
            self.lock.unlock()
            self.conn.cancel()
        }
        timeoutItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func disarmTimeout() {
        lock.lock()
        timeoutItem?.cancel()
        timeoutItem = nil
        lock.unlock()
    }

    func cancelByUser() {
        lock.lock()
        userCancelled = true
        lock.unlock()
        conn.cancel()
    }

    func close() {
        disarmTimeout()
        conn.stateUpdateHandler = nil
        conn.cancel()
    }

    private func mapError(_ error: Error) -> Error {
        lock.lock()
        defer { lock.unlock() }
        if userCancelled { return SyncError.cancelled }
        if timedOut { return SyncError.timeout }
        return error
    }
}
