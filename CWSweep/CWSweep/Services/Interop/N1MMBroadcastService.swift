import CarrierWaveData
import Foundation
import Network

/// UDP broadcast service for N1MM+ compatible contact/radio/score information.
actor N1MMBroadcastService {
    // MARK: Lifecycle

    init(host: String = "127.0.0.1", port: UInt16 = 12_060) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    // MARK: Internal

    func start() {
        let params = NWParameters.udp
        connection = NWConnection(host: host, port: port, using: params)
        connection?.start(queue: .global(qos: .utility))
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }

    /// Broadcast a logged contact in N1MM XML format.
    func broadcastContact(
        callsign: String,
        band: String,
        mode: String,
        frequency: Double,
        rstSent: String,
        rstReceived: String,
        exchangeSent: String,
        exchangeReceived: String,
        myCallsign: String,
        contestName: String,
        score: ContestScoreSnapshot
    ) {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: Date())
        let freqHz = Int(frequency * 1_000_000)

        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <contactinfo>
            <app>CWSweep</app>
            <contestname>\(escapeXML(contestName))</contestname>
            <contestnr>1</contestnr>
            <timestamp>\(timestamp)</timestamp>
            <mycall>\(escapeXML(myCallsign))</mycall>
            <band>\(escapeXML(band))</band>
            <rxfreq>\(freqHz)</rxfreq>
            <txfreq>\(freqHz)</txfreq>
            <operator>\(escapeXML(myCallsign))</operator>
            <mode>\(escapeXML(mode))</mode>
            <call>\(escapeXML(callsign))</call>
            <snt>\(escapeXML(rstSent))</snt>
            <sntnr>\(escapeXML(exchangeSent))</sntnr>
            <rcv>\(escapeXML(rstReceived))</rcv>
            <rcvnr>\(escapeXML(exchangeReceived))</rcvnr>
            <score>\(score.finalScore)</score>
        </contactinfo>
        """

        sendData(xml.data(using: .utf8))
    }

    /// Broadcast radio info (frequency/mode changes).
    func broadcastRadioInfo(
        frequency: Double,
        mode: String,
        myCallsign: String,
        contestName: String
    ) {
        let freqHz = Int(frequency * 1_000_000)

        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <RadioInfo>
            <app>CWSweep</app>
            <StationName>\(escapeXML(myCallsign))</StationName>
            <RadioNr>1</RadioNr>
            <Freq>\(freqHz)</Freq>
            <TXFreq>\(freqHz)</TXFreq>
            <Mode>\(escapeXML(mode))</Mode>
            <OpCall>\(escapeXML(myCallsign))</OpCall>
            <ContestName>\(escapeXML(contestName))</ContestName>
            <IsRunning>False</IsRunning>
        </RadioInfo>
        """

        sendData(xml.data(using: .utf8))
    }

    // MARK: Private

    private var connection: NWConnection?
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port

    private func sendData(_ data: Data?) {
        guard let data, let connection else {
            return
        }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
