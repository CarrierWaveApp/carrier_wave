// AudioWorklet playback for the KiwiSDR stream: a ring-buffer processor fed
// Float32 PCM over the worklet port. We ask the AudioContext to run at the
// receiver's sample rate (~12 kHz); if the browser refuses or clamps it, we
// fall back to a naive linear resample into the context's native rate.

// The processor source ships as a Blob URL so it needs no separate asset
// (Vite's base is /logbook/, which makes URL-based worklet modules brittle).
const WORKLET_SOURCE = `
class CwKiwiRing extends AudioWorkletProcessor {
  constructor() {
    super();
    // ~4 s of audio; prebuffer ~0.25 s before starting to ride out jitter.
    this.buffer = new Float32Array(Math.max(1, Math.floor(sampleRate * 4)));
    this.readIdx = 0;
    this.writeIdx = 0;
    this.filled = 0;
    this.started = false;
    this.prebuffer = Math.floor(sampleRate * 0.25);
    this.port.onmessage = (event) => {
      const samples = event.data;
      for (let i = 0; i < samples.length; i++) {
        if (this.filled === this.buffer.length) {
          // Overrun: drop the oldest sample.
          this.readIdx = (this.readIdx + 1) % this.buffer.length;
          this.filled--;
        }
        this.buffer[this.writeIdx] = samples[i];
        this.writeIdx = (this.writeIdx + 1) % this.buffer.length;
        this.filled++;
      }
    };
  }

  process(_inputs, outputs) {
    const out = outputs[0][0];
    if (!out) return true;
    if (!this.started && this.filled < this.prebuffer) {
      out.fill(0);
      return true;
    }
    this.started = true;
    for (let i = 0; i < out.length; i++) {
      if (this.filled > 0) {
        out[i] = this.buffer[this.readIdx];
        this.readIdx = (this.readIdx + 1) % this.buffer.length;
        this.filled--;
      } else {
        out[i] = 0; // underrun — emit silence until the buffer refills
      }
    }
    return true;
  }
}
registerProcessor('cw-kiwi-ring', CwKiwiRing);
`;

export class KiwiAudioPlayer {
  private constructor(
    private ctx: AudioContext,
    private node: AudioWorkletNode,
    /** Set when the context runs at a different rate than the stream. */
    private resampleRatio: number | null,
    private lastSample = 0,
  ) {}

  static async create(streamRateHz: number): Promise<KiwiAudioPlayer> {
    const rate = Math.round(streamRateHz);
    let ctx: AudioContext;
    try {
      ctx = new AudioContext({ sampleRate: rate });
    } catch {
      ctx = new AudioContext();
    }
    const resampleRatio =
      Math.abs(ctx.sampleRate - rate) > 1 ? ctx.sampleRate / rate : null;

    const url = URL.createObjectURL(
      new Blob([WORKLET_SOURCE], { type: 'application/javascript' }),
    );
    try {
      await ctx.audioWorklet.addModule(url);
    } finally {
      URL.revokeObjectURL(url);
    }

    const node = new AudioWorkletNode(ctx, 'cw-kiwi-ring', {
      numberOfInputs: 0,
      numberOfOutputs: 1,
      outputChannelCount: [1],
    });
    node.connect(ctx.destination);
    await ctx.resume();
    return new KiwiAudioPlayer(ctx, node, resampleRatio);
  }

  /** Queue decoded Int16 PCM from the WASM decoder for playback. */
  push(samples: Int16Array): void {
    let out: Float32Array;
    if (this.resampleRatio === null) {
      out = new Float32Array(samples.length);
      for (let i = 0; i < samples.length; i++) out[i] = samples[i] / 32768;
    } else {
      // Naive linear resample stream→context rate, carrying the previous
      // chunk's final sample so chunk boundaries interpolate smoothly.
      const outLen = Math.floor(samples.length * this.resampleRatio);
      out = new Float32Array(outLen);
      for (let i = 0; i < outLen; i++) {
        const src = i / this.resampleRatio - 1;
        const lo = Math.floor(src);
        const frac = src - lo;
        const a = lo < 0 ? this.lastSample : samples[lo] / 32768;
        const hiIdx = Math.min(lo + 1, samples.length - 1);
        const b = hiIdx < 0 ? this.lastSample : samples[hiIdx] / 32768;
        out[i] = a + (b - a) * frac;
      }
      this.lastSample = samples.length > 0 ? samples[samples.length - 1] / 32768 : 0;
    }
    this.node.port.postMessage(out, [out.buffer]);
  }

  async close(): Promise<void> {
    try {
      this.node.disconnect();
      await this.ctx.close();
    } catch {
      // Already closed — nothing to release.
    }
  }
}
