import CarrierWaveData

// MARK: - ServiceConfiguration

/// Tracks which services are configured/authenticated
struct ServiceConfiguration {
    var qrz: Bool = false
    var pota: Bool = false
    var lofi: Bool = false
    var hamrs: Bool = false
    var lotw: Bool = false
    var clublog: Bool = false
    var eqsl: Bool = false

    func isConfigured(_ serviceType: ServiceType) -> Bool {
        switch serviceType {
        case .qrz: qrz
        case .pota: pota
        case .lofi: lofi
        case .hamrs: hamrs
        case .lotw: lotw
        case .clublog: clublog
        case .eqsl: eqsl
        }
    }
}
