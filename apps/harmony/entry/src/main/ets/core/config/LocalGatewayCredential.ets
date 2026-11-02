import { buffer } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { AppConfigSnapshot, readAppConfig } from './AppConfig';

const LOCAL_GATEWAY_RESOURCE: string = 'gateway-credentials.local.json';

interface LocalGatewayCredential {
  schemaVersion: number;
  gatewayBaseUrl: string;
  gatewayBearerToken: string;
}

/**
 * Current device-test builds carry a shared gateway credential, not the MiniMax
 * key. This is not user authentication or a membership entitlement. The resource
 * is generated locally and must never be checked into source control.
 */
export function readLocalGatewayConfig(context: common.Context): AppConfigSnapshot {
  const config = readAppConfig();
  try {
    const raw = context.resourceManager.getRawFileContentSync(LOCAL_GATEWAY_RESOURCE);
    if (raw.byteLength > 8192) return config;
    const saved = JSON.parse(buffer.from(raw).toString('utf8')) as LocalGatewayCredential;
    if (saved.schemaVersion !== 1 || saved.gatewayBaseUrl !== config.gatewayBaseUrl
      || typeof saved.gatewayBearerToken !== 'string'
      || saved.gatewayBearerToken.length < 32 || saved.gatewayBearerToken.length > 4096
      || !/^[A-Za-z0-9._~+\/-]+=*$/.test(saved.gatewayBearerToken)) return config;
    config.gatewayBearerToken = saved.gatewayBearerToken;
  } catch {
    // Missing or malformed local configuration must not crash or log secrets.
  }
  return config;
}
