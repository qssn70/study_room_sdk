import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { NodeSDK } from '@opentelemetry/sdk-node';

let sdk: NodeSDK | undefined;

export async function startTelemetry() {
  const endpoint = process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT;
  if (!endpoint) return;
  sdk = new NodeSDK({
    serviceName: process.env.OTEL_SERVICE_NAME ?? 'study-room-server',
    traceExporter: new OTLPTraceExporter({ url: endpoint }),
    instrumentations: [getNodeAutoInstrumentations()],
  });
  sdk.start();
}

export async function stopTelemetry() {
  await sdk?.shutdown();
}
