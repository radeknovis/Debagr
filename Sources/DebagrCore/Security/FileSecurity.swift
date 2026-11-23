import Foundation

public enum FileSecurity: Sendable {
  public static let directoryPermissions: Int = 0o700
  public static let filePermissions: Int = 0o600

  public static func dataDirectoryURL(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL {
    if let override = environment["DEBAGR_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !override.isEmpty
    {
      return URL(fileURLWithPath: override, isDirectory: true)
    }
    let appSupport =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support",
        isDirectory: true
      )
    return appSupport.appendingPathComponent("Debagr", isDirectory: true)
  }

  public static func ensureSecureDirectory(_ url: URL) throws {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
      if !isDir.boolValue || isSymbolicLink(url) {
        throw DebagrError(
          code: .storageError,
          category: "security",
          message: "Expected directory at \(url.path) but found non-directory or symlink.",
          recoverable: false
        )
      }
      try setPermissions(directoryPermissions, on: url)
      return
    }

    try fm.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: directoryPermissions]
    )
    try setPermissions(directoryPermissions, on: url)
  }

  public static func writeSecureFile(_ data: Data, to url: URL) throws {
    let parent = url.deletingLastPathComponent()
    try ensureSecureDirectory(parent)

    if isSymbolicLink(url) {
      throw DebagrError(
        code: .storageError,
        category: "security",
        message: "Refusing to write to symbolic link at \(url.path).",
        recoverable: false
      )
    }

    let tempURL = parent.appendingPathComponent(
      ".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
    let fd = open(tempURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(filePermissions))
    if fd < 0 {
      throw DebagrError(
        code: .storageError,
        category: "storage",
        message: "Failed to create secure temporary file at \(tempURL.path): errno \(errno).",
        recoverable: false
      )
    }

    var writeSucceeded = false
    defer {
      close(fd)
      if !writeSucceeded {
        try? FileManager.default.removeItem(at: tempURL)
      }
    }

    try data.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else { return }
      var bytesRemaining = rawBuffer.count
      var offset = 0
      while bytesRemaining > 0 {
        let written = Darwin.write(fd, baseAddress.advanced(by: offset), bytesRemaining)
        if written < 0 {
          if errno == EINTR { continue }
          throw DebagrError(
            code: .storageError,
            category: "storage",
            message: "Failed writing secure file at \(tempURL.path): errno \(errno).",
            recoverable: false
          )
        }
        bytesRemaining -= written
        offset += written
      }
    }

    if fchmod(fd, mode_t(filePermissions)) != 0 {
      throw DebagrError(
        code: .storageError,
        category: "security",
        message: "Failed setting 0600 permissions on \(tempURL.path): errno \(errno).",
        recoverable: false
      )
    }
    fsync(fd)

    if rename(tempURL.path, url.path) != 0 {
      throw DebagrError(
        code: .storageError,
        category: "storage",
        message: "Failed replacing target file at \(url.path): errno \(errno).",
        recoverable: false
      )
    }
    writeSucceeded = true
  }

  public static func verifyRestrictivePermissions(_ url: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else { return true }
    guard !isSymbolicLink(url) else { return false }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue
    else {
      return false
    }
    return (mode & 0o077) == 0
  }

  private static func isSymbolicLink(_ url: URL) -> Bool {
    var st = stat()
    guard lstat(url.path, &st) == 0 else { return false }
    return (st.st_mode & S_IFMT) == S_IFLNK
  }

  private static func setPermissions(_ mode: Int, on url: URL) throws {
    if chmod(url.path, mode_t(mode)) != 0 {
      throw DebagrError(
        code: .storageError,
        category: "security",
        message: "Failed setting permissions on \(url.path): errno \(errno).",
        recoverable: false
      )
    }
  }
}
