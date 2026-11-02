import { describe, expect, it } from '@ohos/hypium';
import { MapKVStorage } from '../../../main/ets/core/data/KVStorage';
import { UserAiSettingsRepository, defaultAiSettings, completionUrl } from '../../../main/ets/core/config/UserAiSettings';
import { PersonalAiClient } from '../../../main/ets/core/network/PersonalAiClient';
import { FetchLike, FetchInit, FetchResponse, DraftSummary, GatewayFailure } from '../../../main/ets/core/network/AiGatewayClient';
import { exportDiaryJson, exportDiaryMarkdown } from '../../../main/ets/core/data/DiaryExport';
import { DiaryEntry } from '../../../main/ets/core/model/Domain';
import { hostedAiClient } from '../../../main/ets/core/network/HostedAiClient';

class TestResponse implements FetchResponse {
  status: number = 200;
  body: string = '{"choices":[{"message":{"content":"我听见了你的感受。"}}]}';
  async text(): Promise<string> { return this.body; }
  async json(): Promise<Record<string, Object>> { return JSON.parse(this.body) as Record<string, Object>; }
}
class TestFetcher implements FetchLike {
  response: TestResponse = new TestResponse();
  url: string = '';
  init: FetchInit | undefined = undefined;
  async fetch(url: string, init: FetchInit): Promise<FetchResponse> {
    this.url = url; this.init = init; return this.response;
  }
}
class HangingFetcher implements FetchLike {
  async fetch(_url: string, _init: FetchInit): Promise<FetchResponse> {
    return new Promise<FetchResponse>(() => {});
  }
}

interface TestMessage { role: string; content: string; }
interface TestBody { model: string; messages: TestMessage[]; }
interface ExportEnvelope { schemaVersion: number; entries: DiaryEntry[]; }

export default function personalSettingsTest() {
  describe('personalSettingsTest', () => {
    it('defaults AI on and isolates settings by account', 0, () => {
      const storage = new MapKVStorage();
      const first = new UserAiSettingsRepository(storage, 'one');
      const second = new UserAiSettingsRepository(storage, 'two');
      expect(first.load().enabled).assertTrue();
      expect(first.load().source).assertEqual('milo');
      const settings = defaultAiSettings(); settings.enabled = false; first.save(settings);
      expect(first.load().enabled).assertFalse();
      expect(second.load().enabled).assertTrue();
      first.clear(); expect(first.load().enabled).assertTrue();
    });
    it('accepts base and full endpoints but rejects credentials and queries in URLs', 0, () => {
      expect(completionUrl('https://example.com/v1/')).assertEqual('https://example.com/v1/chat/completions');
      expect(completionUrl('https://example.com/v1/chat/completions')).assertEqual('https://example.com/v1/chat/completions');
      expect(completionUrl('http://example.com/v1')).assertEqual('');
      expect(completionUrl('https://secret@example.com/v1')).assertEqual('');
      expect(completionUrl('https://example.com/v1?key=secret')).assertEqual('');
    });
    it('sends the current user turn once with the selected model and authorization', 0, async () => {
      const fetcher = new TestFetcher();
      const client = new PersonalAiClient(defaultAiSettings(), 'test-only-key', fetcher);
      const draft: DraftSummary = { mood: { valence: 1, labels: ['舒心'] },
        transcript: [{ role: 'user', text: '今天散步了', ts: 1 }] };
      const result = await client.respond({ draft: draft, userText: '今天散步了' });
      expect(result.ok).assertTrue();
      expect(fetcher.url).assertEqual('https://api.deepseek.com/v1/chat/completions');
      expect(fetcher.init!.headers['Authorization']).assertEqual('Bearer test-only-key');
      const body = JSON.parse(fetcher.init!.body) as TestBody;
      expect(body.model).assertEqual('deepseek-chat');
      expect(body.messages.filter((m: TestMessage) => m.content === '今天散步了').length).assertEqual(1);
    });
    it('tests connectivity without sending any diary', 0, async () => {
      const fetcher = new TestFetcher();
      await new PersonalAiClient(defaultAiSettings(), 'test-only', fetcher).testConnection();
      const body = JSON.parse(fetcher.init!.body) as TestBody;
      expect(body.messages.length).assertEqual(1);
      expect(body.messages[0].content.indexOf('连接测试') >= 0).assertTrue();
    });
    it('returns useful authentication, quota and model errors without exposing server bodies', 0, async () => {
      const fetcher = new TestFetcher();
      fetcher.response.body = 'sensitive provider response';
      const client = new PersonalAiClient(defaultAiSettings(), 'test-only', fetcher);
      fetcher.response.status = 401;
      let result = await client.testConnection() as GatewayFailure;
      expect(result.error.message.indexOf('Key') >= 0).assertTrue();
      fetcher.response.status = 429;
      result = await client.testConnection() as GatewayFailure;
      expect(result.error.message.indexOf('额度') >= 0).assertTrue();
      fetcher.response.status = 404;
      result = await client.testConnection() as GatewayFailure;
      expect(result.error.message.indexOf('不存在') >= 0).assertTrue();
      expect(result.error.message.indexOf('sensitive') < 0).assertTrue();
    });
    it('handles malformed and empty model responses', 0, async () => {
      const fetcher = new TestFetcher();
      const client = new PersonalAiClient(defaultAiSettings(), 'test-only', fetcher);
      fetcher.response.body = 'not json'; expect((await client.testConnection()).ok).assertFalse();
      fetcher.response.body = '{"choices":[]}'; expect((await client.testConnection()).ok).assertFalse();
    });
    it('bounds a hanging connection without relying on fetcher cancellation', 0, async () => {
      const result = await new PersonalAiClient(defaultAiSettings(), 'test-only', new HangingFetcher(), 5).testConnection();
      expect(result.ok).assertFalse();
      expect((result as GatewayFailure).error.message.indexOf('超时') >= 0).assertTrue();
    });
    it('calls the hosted gateway instead of blocking behind a membership placeholder', 0, async () => {
      const fetcher = new TestFetcher();
      fetcher.response.body = '{"text":"来自后台的回复","requestId":"test"}';
      const client = hostedAiClient({ gatewayBaseUrl: 'https://gateway.example.com',
        gatewayBearerToken: 'test-gateway-token', gatewayTimeoutMs: 1000 }, true, fetcher);
      const draft: DraftSummary = { mood: { valence: 0, labels: [] }, transcript: [] };
      expect((await client.open({ draft: draft })).ok).assertTrue();
      expect(fetcher.url).assertEqual('https://gateway.example.com/v1/recall/open');
      expect(fetcher.init!.headers['Authorization']).assertEqual('Bearer test-gateway-token');
      expect((await client.respond({ draft: draft, userText: '今天很好' })).ok).assertTrue();
      expect(fetcher.url).assertEqual('https://gateway.example.com/v1/recall/respond');
      expect((await client.createDiary({ draft: draft })).ok).assertTrue();
      expect(fetcher.url).assertEqual('https://gateway.example.com/v1/recall/diary');
    });
    it('does not send diary data without HTTPS configuration and informed consent', 0, async () => {
      const fetcher = new TestFetcher();
      const draft: DraftSummary = { mood: { valence: 0, labels: [] }, transcript: [] };
      const client = hostedAiClient({ gatewayBaseUrl: '', gatewayBearerToken: '', gatewayTimeoutMs: 1000 }, true, fetcher);
      expect((await client.open({ draft: draft })).ok).assertFalse();
      const noConsent = hostedAiClient({ gatewayBaseUrl: 'https://gateway.example.com',
        gatewayBearerToken: 'test-only', gatewayTimeoutMs: 1000 }, false, fetcher);
      expect((await noConsent.open({ draft: draft })).ok).assertFalse();
      const noCredential = hostedAiClient({ gatewayBaseUrl: 'https://milomood.xyz',
        gatewayBearerToken: '', gatewayTimeoutMs: 1000 }, true, fetcher);
      expect((await noCredential.open({ draft: draft })).ok).assertFalse();
      expect(fetcher.url).assertEqual('');
    });
    it('exports complete Unicode diary data and readable conversations', 0, () => {
      const entries: DiaryEntry[] = [{ id: 'test', createdAt: 1, kind: 'past',
        mood: { valence: 1, labels: ['温暖✨'] }, diaryEnabled: true, diary: '今天\n看见花开。',
        transcript: [{ role: 'user', text: '春天真好', ts: 2 }] }];
      const raw = exportDiaryJson(entries);
      const parsed = JSON.parse(raw) as ExportEnvelope;
      expect(parsed.schemaVersion).assertEqual(1);
      expect(parsed.entries[0].mood.labels[0]).assertEqual('温暖✨');
      expect(parsed.entries[0].diary).assertEqual('今天\n看见花开。');
      expect(exportDiaryMarkdown(entries).indexOf('我：春天真好') >= 0).assertTrue();
      expect(raw.indexOf('apiKey')).assertEqual(-1);
      expect((JSON.parse(exportDiaryJson([])) as ExportEnvelope).entries.length).assertEqual(0);
    });
  });
}
