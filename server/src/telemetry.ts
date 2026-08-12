import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { NodeSDK } from '@opentelemetry/sdk-node';
import { applyE2eTraceMarker } from './telemetry-marker';

let sdk: NodeSDK | undefined;
let shutdownPromise: Promise<void> | undefined;

export async function startTelemetry() {
  const endpoint = process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT;
  if (!endpoint || sdk) return;
  const httpInstrumentation = process.env.STUDY_ROOM_RUNTIME_PROFILE === 'test'
    ? {
        startIncomingSpanHook(request: { headers: Record<string, string | string[] | undefined> }) {
          const attributes: Record<string, string> = {};
          applyE2eTraceMarker(
            {
              setAttribute(name, value) {
                attributes[name] = value;
              },
            },
            request.headers,
            process.env.STUDY_ROOM_RUNTIME_PROFILE,
          );
          return attributes;
        },
      }
    : {};
  const nextSdk = new NodeSDK({
    serviceName: process.env.OTEL_SERVICE_NAME ?? 'study-room-server',
    traceExporter: new OTLPTraceExporter({ url: endpoint }),
    instrumentations: [getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-http': httpInstrumentation,
    })],
  });
  nextSdk.start();
  sdk = nextSdk;
}

export function stopTelemetry(): Promise<void> {
  if (shutdownPromise) return shutdownPromise;
  const activeSdk = sdk;
  sdk = undefined;
  shutdownPromise = (activeSdk?.shutdown() ?? Promise.resolve())
    .finally(() => {
      shutdownPromise = undefined;
    });
  return shutdownPromise;
}
