-- MetricKit telemetry from Carrier Wave iOS app
-- Stores raw MetricKit metric and diagnostic payloads for OOM/crash/performance analysis
CREATE TABLE metrickit_payloads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payload_type TEXT NOT NULL,  -- 'metrics' or 'diagnostics'
    app_version TEXT NOT NULL,
    build_number TEXT NOT NULL,
    device_model TEXT NOT NULL,
    os_version TEXT NOT NULL,
    locale TEXT NOT NULL DEFAULT 'unknown',
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_metrickit_payloads_type ON metrickit_payloads (payload_type, created_at);
CREATE INDEX idx_metrickit_payloads_created_at ON metrickit_payloads (created_at);
CREATE INDEX idx_metrickit_payloads_device ON metrickit_payloads (device_model, os_version, created_at);
