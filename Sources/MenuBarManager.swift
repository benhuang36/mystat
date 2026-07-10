import Cocoa
import Combine

class MenuBarManager {
    static let shared = MenuBarManager()
    
    private var controllers: [MonitorType: StatusItemController] = [:]
    private var cancellable: AnyCancellable?
    
    private init() {
        controllers[.cpu] = StatusItemController(type: .cpu)
        controllers[.memory] = StatusItemController(type: .memory)
        controllers[.disk] = StatusItemController(type: .disk)
        controllers[.network] = StatusItemController(type: .network)
        controllers[.battery] = StatusItemController(type: .battery)
        controllers[.time] = StatusItemController(type: .time)
        controllers[.display] = StatusItemController(type: .display)
        
        setupObservers()
        refreshAll()
    }
    
    private func setupObservers() {
        cancellable = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAll()
            }
    }
    
    private func refreshAll() {
        controllers[.cpu]?.setVisible(UserDefaults.standard.bool(forKey: "showCPU"))
        controllers[.memory]?.setVisible(UserDefaults.standard.bool(forKey: "showMemory"))
        controllers[.disk]?.setVisible(UserDefaults.standard.bool(forKey: "showDisk"))
        controllers[.network]?.setVisible(UserDefaults.standard.bool(forKey: "showNetwork"))
        controllers[.battery]?.setVisible(UserDefaults.standard.bool(forKey: "showBattery"))
        controllers[.time]?.setVisible(UserDefaults.standard.bool(forKey: "showTime"))
        controllers[.display]?.setVisible(UserDefaults.standard.bool(forKey: "showDisplay"))
    }
    
    private func updateStatusItem(for type: MonitorType, show: Bool) {
        controllers[type]?.setVisible(show)
    }
}
