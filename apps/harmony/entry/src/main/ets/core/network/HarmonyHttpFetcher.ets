/**
 * Device implementation of the small fetch contract used by AiGatewayClient.
 *
 * Keeping this adapter separate lets the domain client stay testable while the
 * release app uses HarmonyOS NetworkKit instead of the offline test double.
 */
import { http } from '@kit.NetworkKit';
import { AI_AVAILABLE } from '../config/FeatureFlags';
import {
  type CancelSignal,
  type FetchInit,
  type FetchLike,
  type FetchResponse,
} from './AiGatewayClient';

class HarmonyHttpResponse implements FetchResponse {
  status: number;
  private body: string;

  constructor(status: number, body: string) {
    this.status = status;
    this.body = body;
  }

  async text(): Promise<string> {
    return this.body;
  }

  async json(): Promise<Record<string, Object>> {
    return JSON.parse(this.body) as Record<string, Object>;
  }
}

/** HTTPS-only NetworkKit transport for the on-device AI gateway. */
export class HarmonyHttpFetcher implements FetchLike {
  async fetch(input: string, init: FetchInit): Promise<FetchResponse> {
    // All hosted and personal AI transport stops before creating an HTTP request.
    if (!AI_AVAILABLE) throw new Error('AI_DISABLED');
    if (!input.startsWith('https://')) {
      throw new Error('The production AI gateway must use HTTPS.');
    }
    const request = http.createHttp();
    let destroyed: boolean = false;
    const destroy = (): void => {
      if (!destroyed) {
        destroyed = true;
        request.destroy();
      }
    };
    this.cancelOnSignal(init.signal, destroy);
    try {
      const response = await request.request(input, {
        method: http.RequestMethod.POST,
        header: init.headers,
        extraData: init.body,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 10000,
        readTimeout: 30000,
        maxRedirects: 0,
      });
      const body = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      return new HarmonyHttpResponse(response.responseCode, body);
    } finally {
      destroy();
    }
  }

  private cancelOnSignal(signal: CancelSignal | undefined, destroy: () => void): void {
    if (signal === undefined) {
      return;
    }
    if (signal.cancelled) {
      destroy();
      return;
    }
    signal.onCancel(destroy);
  }
}
