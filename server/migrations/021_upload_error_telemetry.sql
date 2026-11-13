-- Upload error telemetry from client apps
-- Stores anonymized, aggregated error data for identifying systemic upload issues
CREATE TABLE upload_error_telemetry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    callsign TEXT NOT NULL,
    service TEXT NOT NULL,
    category TEXT NOT NULL,
    message_hash TEXT NOT NULL,
    affected_count INTEGER NOT NULL DEFAULT 1,
    is_transient BOOLEAN NOT NULL DEFAULT false,
    app_version TEXT NOT NULL,
    os_version TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_upload_error_telemetry_created_at ON upload_error_telemetry (created_at);
CREATE INDEX idx_upload_error_telemetry_service ON upload_error_telemetry (service, created_at);
CREATE INDEX idx_upload_error_telemetry_category ON upload_error_telemetry (category, created_at);
