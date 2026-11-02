import AppKit

let app = NSApplication.shared
app.appearance = NSAppearance(named: .darkAqua)
app.mainMenu = MainMenu.make()
let delegate = AppDelegate()
app.delegate = delegate
// The first instance created becomes NSDocumentController.shared.
_ = DocumentController()
app.run()
