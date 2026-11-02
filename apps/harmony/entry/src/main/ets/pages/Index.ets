import { KeyboardAvoidMode } from '@kit.ArkUI';
import {
  type DiaryEntry,
  type MoodId,
  type ChatMessage,
  type StickerTemplateId,
  Screen,
} from '../core/model/Domain';
import {
  initialRecallState,
  RecallEvents,
  transition,
  type RecallState,
} from '../core/flow/RecallMachine';
import { PreferencesKVStorage, type KVStorage } from '../core/data/KVStorage';
import { EntryRepository } from '../core/data/EntryRepository';
import { RecallSessionRepository } from '../core/data/RecallSessionRepository';
import { HomeScreen } from '../features/home/HomeScreen';
import { ClassifyScreen } from '../features/recall/ClassifyScreen';
import { NowNoteScreen } from '../features/recall/NowNoteScreen';
import { PastTimeScreen } from '../features/recall/PastTimeScreen';
import { ChatScreen } from '../features/conversation/ChatScreen';
import { DiaryScreen } from '../features/diary/DiaryScreen';
import { TimelineScreen } from '../features/timeline/TimelineScreen';
import { DetailScreen } from '../features/timeline/DetailScreen';
import { CardScreen } from '../features/timeline/CardScreen';
import { StageBackdrop } from '../features/ui/MiloButtons';
import {
  type AiGatewayClient,
} from '../core/network/AiGatewayClient';
import { ConversationController, initialConversationState } from '../features/conversation/ConversationController';
import { FallbackGuide } from '../features/conversation/FallbackGuide';
import { HarmonyHttpFetcher } from '../core/network/HarmonyHttpFetcher';
import { AuthSessionStore } from '../core/auth/AuthSessionStore';
import { AgcAuthProvider } from '../core/auth/AgcAuthProvider';
import { type AuthSession } from '../core/auth/AuthProvider';
import { AuthController } from '../features/auth/AuthController';
import { LoginScreen } from '../features/auth/LoginScreen';
import { AccountScreen } from '../features/auth/AccountScreen';
import { AiSettingsScreen } from '../features/auth/AiSettingsScreen';
import { UserAiSettingsRepository } from '../core/config/UserAiSettings';
import { ApiKeyStore } from '../core/auth/ApiKeyStore';
import { PersonalAiClient, UnavailableAiClient } from '../core/network/PersonalAiClient';
import { hostedAiClient } from '../core/network/HostedAiClient';
import { readLocalGatewayConfig } from '../core/config/LocalGatewayCredential';
import { AI_AVAILABLE, effectiveAiEnabled } from '../core/config/FeatureFlags';
import { PersonalFiles } from '../core/system/PersonalFiles';
import { PrivacyConsentRepository } from '../core/auth/PrivacyConsentRepository';
import { PrivacyConsentScreen } from '../features/legal/PrivacyConsentScreen';
import { common } from '@kit.AbilityKit';

type AuthGate = 'checking' | 'signedOut' | 'signedIn';

@Entry
@Component
struct Index {
  // 状态 & 仓储
  @State state: RecallState = initialRecallState();
  @State entries: DiaryEntry[] = [];
  @State detailEntry: DiaryEntry | undefined = undefined;
  @State cardEntry: DiaryEntry | undefined = undefined;
  @State authGate: AuthGate = 'checking';
  @State accountOpen: boolean = false;
  @State aiSettingsOpen: boolean = false;
  @State privacyAccepted: boolean = false;
  @State privacyError: string = '';
  private storage: KVStorage = new PreferencesKVStorage(getContext(this));
  private privacyRepository: PrivacyConsentRepository = new PrivacyConsentRepository(this.storage);
  private entryRepo: EntryRepository = new EntryRepository(this.storage);
  private draftRepo: RecallSessionRepository = new RecallSessionRepository(this.storage);
  private authController: AuthController = new AuthController({
    provider: new AgcAuthProvider(getContext(this), () => this.privacyRepository.hasAccepted()),
    store: new AuthSessionStore(this.storage),
  });
  private gateway: AiGatewayClient | null = null;
  private chatController: ConversationController | null = null;
  private hasRestored: boolean = false;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.privacyAccepted = this.privacyRepository.hasAccepted();
    const session = this.authController.restore();
    this.authGate = session !== undefined ? 'signedIn' : 'signedOut';
    this.accountOpen = this.authController.isDeletionPending();
    this.refreshEntries();
    if (!this.hasRestored) {
      this.hasRestored = true;
      const saved = this.draftRepo.loadDraft();
      if (saved !== undefined) {
        this.state = saved;
      }
    }
    this.refreshEntryCaches();
  }

  private buildChatController(): ConversationController {
    if (this.chatController !== null) return this.chatController;
    if (this.gateway === null) {
      this.gateway = this.createGateway();
    }
    const gateway = this.gateway;
    const conversationState = initialConversationState();
    conversationState.source = effectiveAiEnabled(this.state.draft.aiEnabled ?? this.aiRepository().load().enabled) ? 'ai' : 'script';
    this.chatController = new ConversationController({
      gateway: gateway,
      newGuide: (d) => new FallbackGuide(d.timeMark ?? '过去的某一天'),
    }, conversationState);
    return this.chatController;
  }

  private createGateway(): AiGatewayClient {
    if (!AI_AVAILABLE) return new UnavailableAiClient('');
    const settings = this.aiRepository().load();
    if (settings.source === 'milo') {
      return hostedAiClient(readLocalGatewayConfig(getContext(this)), settings.consent, new HarmonyHttpFetcher());
    }
    if (!settings.consent) return new UnavailableAiClient('请先到 AI 设置配置模型，并确认发送当前对话。');
    try {
      const key = this.apiKeyStore().read(settings.baseUrl);
      if (!key) return new UnavailableAiClient('尚未填写 API Key，请打开 AI 设置完成配置。');
      return new PersonalAiClient(settings, key, new HarmonyHttpFetcher());
    } catch { return new UnavailableAiClient('无法读取 Key，请解锁设备后到 AI 设置重试。'); }
  }

  private aiRepository(): UserAiSettingsRepository {
    return new UserAiSettingsRepository(this.storage, this.authController.getSession()?.uid ?? 'guest');
  }

  private apiKeyStore(): ApiKeyStore {
    return new ApiKeyStore(this.authController.getSession()?.uid ?? 'guest');
  }

  private personalFiles(): PersonalFiles {
    return new PersonalFiles(getContext(this) as common.UIAbilityContext, this.storage, this.authController.getSession()?.uid ?? 'guest');
  }

  private refreshEntries(): void {
    this.entries = this.entryRepo.list();
  }

  private refreshEntryCaches(): void {
    const id = this.state.screen.entryId;
    if (this.state.screen.name === 'detail' && id !== undefined) {
      this.detailEntry = this.entryRepo.get(id);
    } else {
      this.detailEntry = undefined;
    }
    if (this.state.screen.name === 'card' && id !== undefined) {
      this.cardEntry = this.entryRepo.get(id);
    } else {
      this.cardEntry = undefined;
    }
  }

  private persistDraft(): void {
    this.draftRepo.saveDraft(this.state);
  }

  private clearDraft(): void {
    this.draftRepo.clearDraft();
  }

  private pickMood(moodId: MoodId, labels: string[]): void {
    const next = transition(this.state, RecallEvents.selectMood(moodId, labels));
    if (next !== this.state) {
      this.state = next;
      this.state.draft.aiEnabled = this.aiRepository().load().enabled;
      this.gateway = null;
      this.chatController = null;
      this.persistDraft();
    }
  }

  private classify(kind: 'now' | 'past'): void {
    const next = transition(this.state, RecallEvents.classify(kind));
    if (next !== this.state) {
      this.state = next;
      this.persistDraft();
    }
  }

  private setNote(value: string): void {
    const next = transition(this.state, RecallEvents.setNote(value));
    if (next !== this.state) {
      this.state = next;
      this.persistDraft();
    }
  }

  private setTimeMark(value: string): void {
    const next = transition(this.state, RecallEvents.setTimeMark(value));
    if (next !== this.state) {
      this.chatController = null;
      this.state = next;
      this.persistDraft();
    }
  }

  /** Web behavior: after saving, jump straight to the share-card page. */
  private saveAndShowCard(entry: DiaryEntry): void {
    this.entryRepo.save(entry);
    this.clearDraft();
    const reset = transition(this.state, RecallEvents.reset());
    this.state = { screen: Screen.card(entry.id), draft: reset.draft };
    this.refreshEntries();
    this.refreshEntryCaches();
  }

  private saveNowEntry(note: string): void {
    const entry: DiaryEntry = {
      id: `now-${Date.now()}`,
      createdAt: Date.now(),
      kind: 'now',
      mood: this.state.draft.mood,
      diaryEnabled: false,
    };
    if (note.length > 0) {
      entry.note = note;
    }
    this.saveAndShowCard(entry);
  }

  private savePastEntry(diary: string | undefined, diaryEnabled: boolean): void {
    const draft = this.state.draft;
    const entry: DiaryEntry = {
      id: `past-${Date.now()}`,
      createdAt: Date.now(),
      kind: 'past',
      mood: draft.mood,
      diaryEnabled: diaryEnabled,
      transcript: draft.transcript.slice(),
    };
    if (draft.timeMark !== undefined) {
      entry.timeMark = draft.timeMark;
    }
    if (diary !== undefined) {
      entry.diary = diary;
    }
    this.saveAndShowCard(entry);
  }

  private openDetail(entryId: string): void {
    const next = transition(this.state, RecallEvents.openDetail(entryId));
    if (next !== this.state) {
      this.state = next;
      this.refreshEntryCaches();
    }
  }

  private back(): void {
    const next = transition(this.state, RecallEvents.back());
    if (next !== this.state) {
      this.state = next;
      this.refreshEntryCaches();
      this.persistDraft();
    }
  }

  private async signOut(): Promise<void> {
    await this.authController.signOut();
    this.accountOpen = false;
    this.aiSettingsOpen = false;
    this.gateway = null;
    this.chatController = null;
    this.authGate = 'signedOut';
  }

  build() {
    Stack() {
      StageBackdrop()

      if (!this.privacyAccepted) {
        PrivacyConsentScreen({ errorText: this.privacyError, onAccept: () => {
          try {
            this.privacyRepository.accept();
            this.privacyAccepted = this.privacyRepository.hasAccepted();
            this.privacyError = this.privacyAccepted ? '' : '无法保存同意状态，请重试。';
          } catch {
            this.privacyError = '无法保存同意状态，请检查设备空间后重试。';
          }
        } })
      } else if (this.authGate === 'checking') {
        Column() {
          Text('MILO')
            .fontSize(34)
            .fontFamily('serif')
            .fontWeight(FontWeight.Medium)
            .fontColor('#ffffff')
            .letterSpacing(6)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.authGate === 'signedOut') {
        LoginScreen({
          controller: this.authController,
          onSignedIn: (_session: AuthSession) => {
            this.authGate = 'signedIn';
          },
        })
      } else if (AI_AVAILABLE && this.aiSettingsOpen) {
        AiSettingsScreen({ repository: this.aiRepository(), keyStore: this.apiKeyStore(),
          onBack: () => { this.aiSettingsOpen = false; },
          onSaved: () => {
            this.gateway = null;
            this.chatController = null;
            const next = this.state;
            next.draft.aiEnabled = this.aiRepository().load().enabled;
            this.state = next;
            this.persistDraft();
          },
        })
      } else if (this.accountOpen || this.authController.isDeletionPending()) {
        AccountScreen({
          controller: this.authController,
          entryCount: this.entries.length,
          files: this.personalFiles(),
          keyStore: this.apiKeyStore(),
          aiRepository: this.aiRepository(),
          entries: this.entries,
          onAiSettings: () => { if (AI_AVAILABLE) this.aiSettingsOpen = true; },
          onBack: () => { this.accountOpen = false; },
          onSignOut: () => { void this.signOut(); },
          onClearLocalData: () => {
            this.entryRepo.clear();
            this.clearDraft();
          },
          onDeleted: () => {
            this.state = initialRecallState();
            this.chatController = null;
            this.refreshEntries();
            this.refreshEntryCaches();
            this.accountOpen = false;
            this.authGate = 'signedOut';
          },
        })
      } else if (this.state.screen.name === 'home') {
        HomeScreen({
          entryCount: this.entries.length,
          onNext: (id: MoodId, labels: string[]) => this.pickMood(id, labels),
          onOpenTimeline: () => {
            this.state = transition(this.state, RecallEvents.openTimeline());
          },
          onOpenAccount: () => {
            this.accountOpen = true;
          },
        })
      } else if (this.state.screen.name === 'classify') {
        ClassifyScreen({
          onNow: () => this.classify('now'),
          onPast: () => this.classify('past'),
          onBack: () => this.back(),
        })
      } else if (this.state.screen.name === 'now-note') {
        NowNoteScreen({
          mood: this.state.draft.mood,
          onSave: (note: string) => this.saveNowEntry(note),
          onBack: () => this.back(),
        })
      } else if (this.state.screen.name === 'past-time') {
        PastTimeScreen({
          onNext: (mark: string) => this.setTimeMark(mark),
          onBack: () => this.back(),
        })
      } else if (this.state.screen.name === 'chat') {
        ChatScreen({
          defaultAiEnabled: this.aiRepository().load().enabled,
          onAiSettings: () => { if (AI_AVAILABLE) this.aiSettingsOpen = true; },
          draft: this.state.draft,
          controller: this.buildChatController(),
          onChatChange: (transcript: ChatMessage[], inputText: string, aiEnabled: boolean) => {
            this.state = transition(this.state, RecallEvents.updateChat(transcript, inputText, aiEnabled));
            this.persistDraft();
          },
          onFinish: (_transcript: ChatMessage[]) => {
            const next = transition(this.state, RecallEvents.setDiary(' '));
            this.state = next;
            this.persistDraft();
          },
          onBack: () => this.back(),
        })
      } else if (this.state.screen.name === 'diary') {
        DiaryScreen({
          draft: this.state.draft,
          controller: this.buildChatController(),
          onSave: (diary: string | undefined, enabled: boolean) => this.savePastEntry(diary, enabled),
          onBack: () => this.back(),
        })
      } else if (this.state.screen.name === 'timeline') {
        TimelineScreen({
          entries: this.entries,
          onOpen: (id: string) => this.openDetail(id),
          onBack: () => this.back(),
        })
      } else if (this.state.screen.name === 'detail') {
        DetailScreen({
          entry: this.detailEntry,
          onCard: (id: string) => {
            this.state = { screen: Screen.card(id), draft: this.state.draft };
            this.refreshEntryCaches();
          },
          onBack: () => this.back(),
          onRemove: (id: string) => {
            this.entryRepo.remove(id);
            this.state = transition(this.state, RecallEvents.back());
            this.refreshEntries();
            this.refreshEntryCaches();
          },
        })
      } else if (this.state.screen.name === 'card') {
        CardScreen({
          entry: this.cardEntry,
          onSelect: (template: StickerTemplateId) => {
            if (this.cardEntry !== undefined) {
              this.entryRepo.update(this.cardEntry.id, { stickerTemplate: template });
              this.refreshEntryCaches();
            }
          },
          onDone: () => this.back(),
          onHome: () => {
            this.state = transition(this.state, RecallEvents.reset());
            this.refreshEntryCaches();
          },
        })
      } else {
        Text('MILO')
          .fontSize(28)
          .fontColor('#ffffff')
      }
    }
    .width('100%')
    .height('100%')
  }
}
