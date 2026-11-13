import CarrierWaveData
import Foundation

// MARK: - Unified CW Keyer Path

//
// Transport-agnostic entry points for CW keying. Each method tries the
// available paths in priority order so the remote keyer (and the local
// vim macros / palette / WinKeyer pane) all key the radio without caring
// which transport is in use:
//
//   CW Bridge (BLE) → WinKeyer (USB HID) → active RadioSession's CAT
//   handler (CI-V `1A 02`, Kenwood/Elecraft/Yaesu `KY`, …) over either
//   USB serial or TCP.
//
// Bridge-specific entry points (memory slots, status flags) live in
// `RadioManager+Bridge.swift` because they don't have a sensible
// fallback when no bridge is attached.
//

extension RadioManager {
    /// Unified CW send: routes through whichever keyer path is wired, in
    /// priority order CW Bridge → WinKeyer → active radio's CAT handler
    /// (USB serial or TCP). Returns true if some path acked the send.
    @discardableResult
    func sendCW(_ text: String, fallback winKeyer: WinKeyerManager) async -> Bool {
        if isBridgeKeyerAvailable {
            await bridgeSendCW(text)
            return true
        }
        if winKeyer.isConnected {
            await winKeyer.sendText(text)
            return true
        }
        if let id = activeRadioId, let session = sessions[id] {
            return await session.sendCW(text)
        }
        return false
    }

    /// Unified CW abort: stops whichever keyer path is wired.
    @discardableResult
    func stopCW(fallback winKeyer: WinKeyerManager) async -> Bool {
        if isBridgeKeyerAvailable {
            await bridgeStopCW()
            return true
        }
        if winKeyer.isConnected {
            // WinKeyer doesn't expose an abort today; the bridge keyer/CAT
            // paths cover the cases users actually hit. Returning true here
            // would lie; return false so the caller can surface "no abort".
            return false
        }
        if let id = activeRadioId, let session = sessions[id] {
            return await session.abortCW()
        }
        return false
    }

    /// Unified CW speed set: routes through CW Bridge if connected,
    /// otherwise falls back to WinKeyer. CAT keying speed is set on the
    /// radio itself and is not adjustable from this path.
    @discardableResult
    func setCWSpeed(_ wpm: Int, fallback winKeyer: WinKeyerManager) async -> Bool {
        let clamped = UInt8(max(5, min(60, wpm)))
        if isBridgeKeyerAvailable {
            await bridgeSetCWSpeed(clamped)
            return true
        }
        if winKeyer.isConnected {
            await winKeyer.setSpeed(clamped)
            return true
        }
        return false
    }

    /// True iff *any* CW path can transmit right now: bridge, WinKeyer, or
    /// the active radio's CAT handler. Drives the remote-keyer availability
    /// signal so iOS surfaces "send" controls whenever Sweep can actually key.
    /// CAT-keying support is reported optimistically as long as a radio is
    /// connected; the actual `sendCW` call returns false when the protocol
    /// handler doesn't expose CW encoding.
    func cwKeyerAvailable(fallback winKeyer: WinKeyerManager) -> Bool {
        if isBridgeKeyerAvailable {
            return true
        }
        if winKeyer.isConnected {
            return true
        }
        guard let id = activeRadioId else {
            return false
        }
        return sessions[id] != nil
    }
}
