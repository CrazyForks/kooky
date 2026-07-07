import AppKit
import KookyKit

CrashForensics.install()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
