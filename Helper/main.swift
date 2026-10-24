import Foundation

// Root launchd daemon (registered by the app via SMAppService). Its only job is fan writes.
let service = HelperService()
service.start()
let listener = NSXPCListener(machServiceName: HelperConstants.machService)
listener.delegate = service
listener.resume()
dispatchMain()
