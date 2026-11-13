// One live KiwiSDR listening session: websocket through the server's
// /v1/websdr/stream bridge, the KiwiSDR handshake in TS, frame decode via the
// shared WASM KiwiAudioDecoder, playback via KiwiAudioPlayer.
//
// Handshake (mirrors the iOS KiwiSDRClient):
//   → SET auth t=kiwi p=#
//   ← MSG … sample_rate=<rate>      (within a 30-message budget; badp /
//                                    too_busy>0 / MSG down / redirect abort)
//   → SET AR OK in=<rate> out=<rate>
//   → SET ident_user=CarrierWave
//   → SET compression=1
//   → SET mod=… (shared WASM tune_command — CW carrier offset included)
//   → SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50
//   → SET keepalive                 (every 5 s)

import {
  createKiwiDecoder,
  kiwiCheckServerError,
  kiwiParseMsgValue,
  kiwiTuneCommand,
  type KiwiAudioDecoder,
} from '../wasm';
import { KiwiAudioPlayer } from './audioPlayer';
import type { KiwiReceiver } from './types';

export type ListenPhase = 'connecting' | 'handshake' | 'playing' | 'stopped' | 'error';

export interface ListenCallbacks {
  onPhase: (phase: ListenPhase, detail?: string) => void;
  /** Smoothed s-meter reading in dBm. */
  onSMeter: (dbm: number) => void;
}

const HANDSHAKE_MESSAGE_BUDGET = 30;
const KEEPALIVE_MS = 5000;

export class KiwiListener {
  private ws: WebSocket | null = null;
  private decoder: KiwiAudioDecoder | null = null;
  private player: KiwiAudioPlayer | null = null;
  private keepalive: number | null = null;
  private handshakeBudget = HANDSHAKE_MESSAGE_BUDGET;
  private sampleRate: number | null = null;
  private finished = false;

  private constructor(
    private receiver: KiwiReceiver,
    private frequencyKhz: number,
    private mode: string,
    private callbacks: ListenCallbacks,
  ) {}

  /** Open a session and start the handshake. Stop any previous session first. */
  static async start(
    receiver: KiwiReceiver,
    frequencyKhz: number,
    mode: string,
    callbacks: ListenCallbacks,
  ): Promise<KiwiListener> {
    const listener = new KiwiListener(receiver, frequencyKhz, mode, callbacks);
    await listener.open();
    return listener;
  }

  private async open(): Promise<void> {
    this.callbacks.onPhase('connecting');
    // createKiwiDecoder also guarantees the WASM module is initialized, so the
    // sync helpers (kiwiParseMsgValue, …) are safe on the hot path below.
    this.decoder = await createKiwiDecoder();

    const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
    const params = new URLSearchParams({
      host: this.receiver.host,
      port: String(this.receiver.port),
    });
    const ws = new WebSocket(
      `${scheme}://${window.location.host}/v1/websdr/stream?${params}`,
    );
    ws.binaryType = 'arraybuffer';
    this.ws = ws;

    ws.onopen = () => {
      this.callbacks.onPhase('handshake');
      this.send('SET auth t=kiwi p=#');
    };
    ws.onmessage = (event) => this.handleMessage(event);
    ws.onerror = () => this.fail('connection error');
    ws.onclose = () => {
      if (!this.finished) this.fail('connection closed');
    };
  }

  private handleMessage(event: MessageEvent): void {
    if (!this.decoder || this.finished) return;

    // The bridge is a byte pipe; KiwiSDR sends MSG text inside binary frames,
    // so everything funnels through the WASM decoder's classifier.
    const data =
      event.data instanceof ArrayBuffer
        ? new Uint8Array(event.data)
        : new TextEncoder().encode(String(event.data));

    const frame = this.decoder.handleFrame(data);
    try {
      switch (frame.kind) {
        case 'audio':
          if (frame.samples && this.player) this.player.push(frame.samples);
          if (frame.sMeter !== undefined) {
            this.callbacks.onSMeter(frame.sMeter / 10 - 127);
          }
          break;
        case 'text':
          this.handleText(frame.text ?? '');
          break;
        case 'adpcmReset':
          break; // decoder state already reset in WASM
        case 'redirect':
          this.fail('receiver redirected the connection — try another receiver');
          break;
        case 'disconnected':
          this.fail(`receiver disconnected (${frame.text ?? 'no reason given'})`);
          break;
        default:
          break; // 'none' — unusable frame
      }
    } finally {
      frame.free();
    }
  }

  private handleText(text: string): void {
    // Our proxy signals upstream-connect failures with its own MSG line.
    const proxyError = kiwiParseMsgValue(text, 'cw_proxy_error');
    if (proxyError) {
      this.fail(`could not reach the receiver (${proxyError})`);
      return;
    }

    if (this.sampleRate !== null) return; // handshake already complete

    const error = kiwiCheckServerError(text);
    if (error) {
      this.fail(error.startsWith('redirect:') ? 'receiver redirected — try another receiver' : error);
      return;
    }

    const rateText = kiwiParseMsgValue(text, 'sample_rate');
    if (rateText) {
      const rate = Math.round(parseFloat(rateText));
      if (!Number.isFinite(rate) || rate <= 0) {
        this.fail('receiver sent an invalid sample rate');
        return;
      }
      void this.completeHandshake(rate);
      return;
    }

    this.handshakeBudget -= 1;
    if (this.handshakeBudget <= 0) {
      this.fail('receiver never sent a sample rate');
    }
  }

  private async completeHandshake(rate: number): Promise<void> {
    this.sampleRate = rate;
    this.send(`SET AR OK in=${rate} out=${rate}`);
    this.send('SET ident_user=CarrierWave');
    this.send('SET compression=1');
    this.send(kiwiTuneCommand(this.frequencyKhz, this.mode, this.frequencyKhz / 1000));
    this.send('SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50');
    this.keepalive = window.setInterval(() => this.send('SET keepalive'), KEEPALIVE_MS);

    try {
      this.player = await KiwiAudioPlayer.create(rate);
    } catch (e) {
      this.fail(e instanceof Error ? e.message : 'audio playback unavailable');
      return;
    }
    if (!this.finished) this.callbacks.onPhase('playing');
  }

  private send(command: string): void {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(command);
  }

  private fail(detail: string): void {
    if (this.finished) return;
    this.teardown();
    this.callbacks.onPhase('error', detail);
  }

  stop(): void {
    if (this.finished) return;
    this.teardown();
    this.callbacks.onPhase('stopped');
  }

  private teardown(): void {
    this.finished = true;
    if (this.keepalive !== null) {
      window.clearInterval(this.keepalive);
      this.keepalive = null;
    }
    if (this.ws) {
      this.ws.onclose = null;
      this.ws.onerror = null;
      this.ws.onmessage = null;
      try {
        this.ws.close();
      } catch {
        // already closed
      }
      this.ws = null;
    }
    void this.player?.close();
    this.player = null;
    this.decoder?.free();
    this.decoder = null;
  }
}
