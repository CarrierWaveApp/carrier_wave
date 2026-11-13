use axum::Extension;
use metrics_exporter_prometheus::PrometheusHandle;

pub async fn get_metrics(Extension(handle): Extension<PrometheusHandle>) -> String {
    handle.render()
}
