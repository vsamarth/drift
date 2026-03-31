import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let storageChannelName = "drift/storage_access"
  private let bookmarkKey = "storage.bookmark"
  private let bookmarkPathKey = "storage.bookmark.path"
  private var activeScopedUrl: URL?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: storageChannelName,
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.setMethodCallHandler(handleStorageMethodCall)
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func handleStorageMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]

    do {
      switch call.method {
      case "pickDirectory":
        let initialDirectory = args?["initialDirectory"] as? String
        result(try pickDirectory(initialDirectory: initialDirectory))
      case "restorePersistedAccess":
        let path = (args?["path"] as? String) ?? ""
        try restorePersistedAccess(path: path)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(
        FlutterError(
          code: "storage_access_error",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func pickDirectory(initialDirectory: String?) throws -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose folder"
    if let initialDirectory, !initialDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      panel.directoryURL = URL(fileURLWithPath: initialDirectory, isDirectory: true)
    }

    let response = panel.runModal()
    guard response == .OK, let url = panel.url else {
      return nil
    }

    try persistBookmark(for: url)
    return url.path
  }

  private func persistBookmark(for url: URL) throws {
    let bookmark = try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    UserDefaults.standard.set(url.path, forKey: bookmarkPathKey)
    _ = beginAccess(for: url)
  }

  private func restorePersistedAccess(path: String) throws {
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else {
      return
    }

    let defaults = UserDefaults.standard
    guard
      defaults.string(forKey: bookmarkPathKey) == trimmedPath,
      let bookmark = defaults.data(forKey: bookmarkKey)
    else {
      return
    }

    var isStale = false
    let url = try URL(
      resolvingBookmarkData: bookmark,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    if isStale {
      try persistBookmark(for: url)
      return
    }

    _ = beginAccess(for: url)
  }

  @discardableResult
  private func beginAccess(for url: URL) -> Bool {
    if activeScopedUrl?.path == url.path {
      return true
    }

    activeScopedUrl?.stopAccessingSecurityScopedResource()
    let didStart = url.startAccessingSecurityScopedResource()
    if didStart {
      activeScopedUrl = url
    } else {
      activeScopedUrl = nil
    }
    return didStart
  }
}
