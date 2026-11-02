import { AppConfigSnapshot, isGatewayConfigured } from '../config/AppConfig';
import { AiGatewayClient, FetchLike, HttpAiGatewayClient } from './AiGatewayClient';
import { UnavailableAiClient } from './PersonalAiClient';

/** Hosting and any future subscription authorization belong to the server, not a UI toggle. */
export function hostedAiClient(config: AppConfigSnapshot, consent: boolean, fetcher: FetchLike): AiGatewayClient {
  if (!isGatewayConfigured(config)) {
    return new UnavailableAiClient('MILO 后台尚未配置公网 HTTPS 地址，暂时使用本地引导。');
  }
  if (!consent) {
    return new UnavailableAiClient('请在 AI 设置确认将当前情绪和对话发送给 MILO 后台及 MiniMax。');
  }
  if (!config.gatewayBearerToken.trim()) {
    return new UnavailableAiClient('此版本尚未完成 AI 服务配置，请安装最新版本；本地记录仍可使用。');
  }
  return new HttpAiGatewayClient({ baseUrl: config.gatewayBaseUrl,
    bearerToken: config.gatewayBearerToken, timeoutMs: config.gatewayTimeoutMs, fetcher: fetcher });
}
