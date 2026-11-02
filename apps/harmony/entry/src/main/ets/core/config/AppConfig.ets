/**
 * Public gateway address. The local build credential is loaded separately
 * by LocalGatewayCredential; never put gateway or provider secrets here.
 * Builds without that local resource keep the offline fallback available.
 */

export const GATEWAY_BASE_URL: string = 'https://milomood.xyz';
export const GATEWAY_BEARER_TOKEN: string = '';
export const GATEWAY_TIMEOUT_MS: number = 30000;

export interface AppConfigSnapshot {
  gatewayBaseUrl: string;
  gatewayBearerToken: string;
  gatewayTimeoutMs: number;
}

export function readAppConfig(): AppConfigSnapshot {
  return {
    gatewayBaseUrl: GATEWAY_BASE_URL,
    gatewayBearerToken: GATEWAY_BEARER_TOKEN,
    gatewayTimeoutMs: GATEWAY_TIMEOUT_MS,
  };
}

export function isGatewayConfigured(config: AppConfigSnapshot): boolean {
  return config.gatewayBaseUrl.startsWith('https://');
}
