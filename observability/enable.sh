#!/bin/bash
# Source this from an up-script (or a shell) to switch the observability CONTEXT on:
#   . ../shared/observability/enable.sh
# It activates the compose profile and — once the agent jar is on disk — the OTel Java agent in
# every JVM service. Without this, `docker compose up` brings the system alone: no Prometheus,
# Grafana, Loki, Tempo, cadvisor, node-exporter, and no -javaagent (which would only log export
# failures against a Tempo that is not there).
_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_agent="$_here/otel/opentelemetry-javaagent.jar"
export COMPOSE_PROFILES=observability
if [ ! -f "$_agent" ]; then
    echo "fetching the OpenTelemetry Java agent..."
    mkdir -p "$_here/otel"
    curl -sfL -o "$_agent" \
        "https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.29.0/opentelemetry-javaagent.jar" \
        || { echo "WARNING: could not fetch the OTel agent; JVM services start without tracing"; rm -f "$_agent"; }
fi
# a -javaagent pointing at a missing file aborts the JVM — only point at a jar that exists
if [ -f "$_agent" ]; then
    export OTEL_JAVA_TOOL_OPTIONS="-javaagent:/otel/opentelemetry-javaagent.jar"
fi
unset _here _agent
