import { UserAiSettingsRepository, defaultAiSettings, MODEL_PRESETS, completionUrl, UserAiSettings } from '../../core/config/UserAiSettings';
import { ApiKeyStore } from '../../core/auth/ApiKeyStore';
import { PersonalAiClient } from '../../core/network/PersonalAiClient';
import { HarmonyHttpFetcher } from '../../core/network/HarmonyHttpFetcher';
import { GatewayFailure } from '../../core/network/AiGatewayClient';
import { readAppConfig, isGatewayConfigured } from '../../core/config/AppConfig';
import { AI_AVAILABLE } from '../../core/config/FeatureFlags';
import { MiloBackNode, MiloPrimaryButton, MiloBackLink } from '../ui/MiloButtons';

@Component
export struct AiSettingsScreen {
  repository: UserAiSettingsRepository | null = null;
  keyStore: ApiKeyStore | null = null;
  onBack: () => void = () => {};
  onSaved: () => void = () => {};
  @State aiEnabled: boolean = true;
  @State source: string = 'milo';
  @State provider: string = 'deepseek';
  @State baseUrl: string = '';
  @State model: string = '';
  @State apiKey: string = '';
  @State consent: boolean = false;
  @State busy: boolean = false;
  @State status: string = '';
  @State selectedIndex: number = 0;
  private keyReadable: boolean = true;

  aboutToAppear(): void {
    if (!AI_AVAILABLE) { this.onBack(); return; }
    const saved = this.repository?.load() ?? defaultAiSettings();
    this.aiEnabled = saved.enabled;
    this.source = saved.source;
    this.provider = saved.provider;
    this.baseUrl = saved.baseUrl;
    this.model = saved.model;
    this.consent = saved.consent;
    this.selectedIndex = Math.max(0, MODEL_PRESETS.findIndex((p) => p.id === this.provider));
    try { this.apiKey = this.keyStore?.read(this.baseUrl) ?? ''; } catch {
      this.keyReadable = false;
      this.status = '无法读取安全存储，请解锁设备后重新进入此页。';
    }
  }
  aboutToDisappear(): void { this.apiKey = ''; }
  private snapshot(): UserAiSettings {
    return { enabled: this.aiEnabled, source: this.source, provider: this.provider, baseUrl: this.baseUrl.trim(), model: this.model.trim(), consent: this.consent };
  }
  private valid(): boolean {
    if (!completionUrl(this.baseUrl) || !this.model.trim() || !this.apiKey.trim()) {
      this.status = '请填写 HTTPS 接口地址、模型名称和 API Key。'; return false;
    }
    if (!this.consent) { this.status = '请先确认将当前对话发送给所选模型服务商。'; return false; }
    return true;
  }
  private save(): void {
    if (!AI_AVAILABLE || this.busy) return;
    if (!this.keyReadable) { this.status = '请解锁设备后重新进入此页，避免覆盖原有 Key。'; return; }
    if (this.source === 'personal' && this.aiEnabled && !this.valid()) return;
    if (this.source === 'milo' && this.aiEnabled && !this.consent) {
      this.status = '请先确认将当前情绪和对话发送给 MILO 后台及 MiniMax。'; return;
    }
    try {
      if (this.source === 'personal') this.keyStore?.save(this.apiKey.trim(), this.baseUrl);
      this.repository?.save(this.snapshot());
      this.status = this.source === 'milo' && !isGatewayConfigured(readAppConfig())
        ? '设置已保存，但此安装包尚未配置后台 HTTPS 地址；目前仍是本地引导。'
        : '设置已保存，下次 AI 请求将使用此配置。';
      this.onSaved();
    } catch { this.status = '保存失败，设备安全存储暂不可用；Key 未写入普通文件。'; }
  }
  private async test(): Promise<void> {
    if (!AI_AVAILABLE || this.busy || !this.valid()) return;
    this.busy = true;
    this.status = '正在连接模型，最长等待 30 秒…';
    const result = await new PersonalAiClient(this.snapshot(), this.apiKey, new HarmonyHttpFetcher()).testConnection();
    this.status = result.ok ? '连接成功，可以保存并开始使用。' : (result as GatewayFailure).error.message;
    this.busy = false;
  }
  build() {
    Column({ space: 16 }) {
      Row({ space: 16 }) {
        MiloBackNode({ onTap: () => { if (!this.busy) this.onBack(); } })
        Text('AI 设置').fontSize(22).fontColor('#eae6ff')
      }.width('100%')
      Scroll() {
        Column({ space: 18 }) {
          Row() {
            Text('默认开启 AI').fontSize(16).fontColor('#eae6ff')
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.aiEnabled }).onChange((v: boolean) => { this.aiEnabled = v; })
          }.width('100%')
          Text('关闭后使用本地引导，记录与导出始终可用。').fontSize(13).fontColor('#9d97b7')
          Row({ space: 10 }) {
            Button('自己的模型').backgroundColor(this.source === 'personal' ? '#7969c8' : '#242039')
              .onClick(() => { if (this.source !== 'personal') this.consent = false; this.source = 'personal'; })
            Button('MILO 默认模型').backgroundColor(this.source === 'milo' ? '#7969c8' : '#242039')
              .onClick(() => { if (this.source !== 'milo') this.consent = false; this.source = 'milo'; })
          }
          if (this.source === 'personal') {
            Text('服务商').fontColor('#eae6ff').alignSelf(ItemAlign.Start)
            Select(MODEL_PRESETS.map((p): SelectOption => ({ value: p.label }))).selected(this.selectedIndex)
              .value(MODEL_PRESETS[this.selectedIndex].label).width('100%').fontColor('#eae6ff')
              .onSelect((index: number) => {
                this.selectedIndex = index;
                this.provider = MODEL_PRESETS[index].id;
                this.baseUrl = MODEL_PRESETS[index].baseUrl;
                this.model = MODEL_PRESETS[index].model;
                this.apiKey = '';
                this.consent = false;
                this.status = '已切换服务商，请填写对应 Key。';
              })
            Text('接口地址（Base URL 或完整 /chat/completions 地址）').fontSize(13).fontColor('#aaa2c6')
            TextInput({ text: this.baseUrl, placeholder: 'https://api.example.com/v1' }).fontColor('#eae6ff')
              .backgroundColor('#242039').onChange((v: string) => { this.baseUrl = v; this.consent = false; })
            TextInput({ text: this.model, placeholder: '模型名称，例如 qwen-plus' }).fontColor('#eae6ff')
              .backgroundColor('#242039').onChange((v: string) => { this.model = v; })
            TextInput({ text: this.apiKey, placeholder: 'API Key' }).type(InputType.Password).fontColor('#eae6ff')
              .backgroundColor('#242039').onChange((v: string) => { this.apiKey = v; })
            Text('支持 OpenAI 兼容 Chat Completions 接口。服务商默认地址可编辑；地区或套餐不同，请使用控制台给出的地址和模型名称。')
              .fontSize(12).fontColor('#aaa2c6').lineHeight(20)
            Row({ space: 8 }) {
              Checkbox().select(this.consent).onChange((v: boolean) => { this.consent = v; })
              Text('我同意将当前情绪和对话发送到上述地址；费用由该服务商按我的 Key 计费。')
                .fontSize(13).fontColor('#c9befc').layoutWeight(1)
            }
            Text('Key 仅保存于本设备系统安全存储，不经过 MILO 服务器，也不会包含在日记导出中。连接测试只发送一条测试问候，可能产生少量用量。')
              .fontSize(12).fontColor('#aaa2c6').lineHeight(20)
            MiloBackLink({ label: this.busy ? '正在测试…' : '测试连接', onTap: () => { void this.test(); } })
            MiloBackLink({ label: '删除已保存的 Key', onTap: () => {
              try {
                this.keyStore?.clear();
                this.apiKey = '';
                this.consent = false;
                const saved = this.repository?.load() ?? defaultAiSettings();
                saved.consent = false;
                this.repository?.save(saved);
                this.status = '已删除本机 Key，重新使用时需再次确认数据发送。'; this.onSaved();
              }
              catch { this.status = '删除失败，请重试。'; }
            } }).enabled(!this.busy)
          } else {
            Text('默认由 MILO 后台调用 MiniMax，无需填写个人 Key。MiniMax 密钥仅保存在服务器。')
              .fontSize(14).lineHeight(24).fontColor('#c9befc')
            Text(isGatewayConfigured(readAppConfig()) ? '后台地址已配置，实际可用性以请求结果为准。' : '尚未接通：此安装包缺少后台公网 HTTPS 地址。')
              .fontSize(13).fontColor('#aaa2c6')
            Row({ space: 8 }) {
              Checkbox().select(this.consent).onChange((v: boolean) => { this.consent = v; })
              Text('我同意将当前情绪和对话经 MILO 后台发送给 MiniMax，用于生成回复和日记；不会发送全部历史日记。')
                .fontSize(13).fontColor('#c9befc').layoutWeight(1)
            }
            Text('MILO 星球会员').fontSize(22).fontColor('#eae6ff')
            Text('月订阅方案 · 拟定 ¥12 / 月').fontSize(19).fontColor('#c9befc')
            Text('计划权益：每月 300 次 AI 回复或日记生成。无需自己配置 Key。额度用尽仍可本地记录，或切换自己的模型。')
              .fontSize(14).lineHeight(24).fontColor('#c9befc')
            Text('订阅筹备中，暂不收费。正式开通前会展示最终价格、额度、续费与取消说明。')
              .fontSize(13).lineHeight(22).fontColor('#aaa2c6')
            Button('订阅暂未开放').enabled(false)
          }
        }.width('100%').padding({ bottom: 20 }).enabled(!this.busy)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      if (this.status) { Text(this.status).fontSize(13).fontColor('#c9befc').width('100%') }
      MiloPrimaryButton({ label: '保存设置', active: !this.busy, onTap: () => this.save() })
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: 20, bottom: 24 })
  }
}
