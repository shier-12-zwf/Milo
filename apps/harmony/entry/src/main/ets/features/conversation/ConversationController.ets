import { type Draft, type ChatMessage, type MoodState } from '../../core/model/Domain';
import {
  type AiGatewayClient,
  type GatewayError,
  type GatewayResult,
  type GatewaySuccess,
  type GatewayFailure,
  isFailure,
  type DraftSummary,
} from '../../core/network/AiGatewayClient';
import { FallbackGuide, fallbackDiary, wantsToPause } from './FallbackGuide';
import { AI_AVAILABLE } from '../../core/config/FeatureFlags';

export type ConversationSource = 'ai' | 'script';

export interface ConversationState {
  /** Last source that produced a message; flips to `script` after first failure. */
  source: ConversationSource;
  /** Persistable script step so the guide resumes where it left off. */
  fallbackStep: number;
  /** Last gateway failure, retained for diagnostics without interrupting chat. */
  lastError: GatewayError | undefined;
}

export function initialConversationState(): ConversationState {
  return {
    source: 'ai',
    fallbackStep: 0,
    lastError: undefined,
  };
}

export interface CompleteConversation {
  state: ConversationState;
  message: ChatMessage;
  usedAi: boolean;
}

export interface CompleteDiary {
  state: ConversationState;
  diary: string;
  usedAi: boolean;
}

/** Result type that distinguishes scripted vs AI outcomes for the UI layer. */
export type OpenResult = CompleteConversation;
export type RespondResult = CompleteConversation;
export type DiaryResult = CompleteDiary;

export interface ConversationControllerDeps {
  gateway: AiGatewayClient;
  /** Test seam for fake gateways; the device transport still enforces AI_AVAILABLE. */
  aiAvailable?: boolean;
  /** Returns the local fallback guide for the current draft. */
  newGuide: (draft: Draft) => FallbackGuide;
}

export class ConversationController {
  private deps: ConversationControllerDeps;
  private state: ConversationState;
  private guide: FallbackGuide | undefined;
  private aiAvailable: boolean;

  constructor(deps: ConversationControllerDeps, state?: ConversationState) {
    this.deps = deps;
    this.state = state ?? initialConversationState();
    this.aiAvailable = deps.aiAvailable ?? AI_AVAILABLE;
    this.enforceAvailability();
  }

  /** Read-only snapshot for tests and persistence. */
  getState(): ConversationState {
    return this.state;
  }

  /** Restore a previously persisted state (e.g. after process restart). */
  restore(step: number): void {
    this.state.fallbackStep = step;
    if (this.guide !== undefined) {
      this.guide.restoreStep(step);
    }
  }

  /** Replace the whole controller state; used by the UI on cold-start hydration. */
  restoreState(state: ConversationState): void {
    this.state = {
      source: state.source,
      fallbackStep: state.fallbackStep,
      lastError: state.lastError,
    };
    this.enforceAvailability();
    if (this.guide !== undefined) {
      this.guide.restoreStep(state.fallbackStep);
    }
  }

  /** Send the opening greeting; AI first, then switch to the scripted guide. */
  async open(draft: Draft): Promise<OpenResult> {
    this.ensureGuide(draft);
    const aiText = await this.tryAi(draft, () => this.deps.gateway.open({ draft: this.toSummary(draft) as DraftSummary }));
    if (aiText !== undefined) {
      return {
        state: this.state,
        message: this.assistantMessage(aiText),
        usedAi: true,
      };
    }
    const scripted = this.guide!.opening();
    this.syncFallbackStep();
    return {
      state: this.state,
      message: this.assistantMessage(scripted),
      usedAi: false,
    };
  }

  /**
   * Reply to the user's latest message. The transcript we hand the gateway
   * already contains the user's line, so an AI success is recorded as a
   * fresh assistant message; a failure yields the next scripted reply.
   */
  async respond(draft: Draft, userText: string, ts: number): Promise<RespondResult> {
    this.ensureGuide(draft);
    this.restoreTranscriptProgress(draft);
    if (wantsToPause(userText)) {
      const reply = this.guide!.next(userText);
      this.syncFallbackStep();
      return { state: this.state, message: this.assistantMessage(reply), usedAi: false };
    }
    const enriched: Draft = cloneDraftWith(draft, this.withUserLine(draft, userText, ts));
    const aiText = await this.tryAi(enriched, () => this.deps.gateway.respond({ draft: this.toSummary(enriched) as DraftSummary, userText: userText }));
    if (aiText !== undefined) {
      this.guide!.restoreStep(this.guide!.currentStep() + 1);
      this.syncFallbackStep();
      return {
        state: this.state,
        message: this.assistantMessage(aiText),
        usedAi: true,
      };
    }
    const scripted = this.guide!.next(userText);
    this.syncFallbackStep();
    return {
      state: this.state,
      message: this.assistantMessage(scripted),
      usedAi: false,
    };
  }

  /** Generate the diary; falls back to the local first-person generator. */
  async createDiary(draft: Draft): Promise<DiaryResult> {
    this.enforceAvailability();
    if (this.state.source !== 'script' && draft.transcript.length <= 32) {
      try {
        const result = await this.deps.gateway.createDiary({ draft: this.toSummary(draft, false) as DraftSummary });
        if (result.ok === true) {
          const success: GatewaySuccess = result as GatewaySuccess;
          const trimmed = success.text.trim();
          if (trimmed.length > 0) {
            return { state: this.state, diary: trimmed, usedAi: true };
          }
        }
      } catch {
        // A provider exception must not prevent saving the local diary.
      }
    }
    return {
      state: this.state,
      diary: fallbackDiary(draft),
      usedAi: false,
    };
  }

  /** Soft progress checkpoint; callers must keep saving and input available. */
  isScriptComplete(): boolean {
    if (this.guide === undefined) {
      return false;
    }
    return this.guide.isWrappingUp();
  }

  /** Public for tests: did we already fall back to the script? */
  isOnFallback(): boolean {
    return this.state.source === 'script';
  }

  private ensureGuide(draft: Draft): void {
    if (this.guide === undefined) {
      this.guide = this.deps.newGuide(draft);
      this.guide.restoreStep(this.state.fallbackStep);
    }
  }

  /** The supplied transcript ends before the current user message. */
  private restoreTranscriptProgress(draft: Draft): void {
    let userTurns = 0;
    for (let index = 0; index < draft.transcript.length; index += 1) {
      if (draft.transcript[index].role === 'user') userTurns += 1;
    }
    this.guide!.restoreStep(Math.max(this.guide!.currentStep(), userTurns));
    this.syncFallbackStep();
  }

  private syncFallbackStep(): void {
    if (this.guide !== undefined) {
      this.state.fallbackStep = this.guide.currentStep();
    }
  }

  private async tryAi(
    draft: Draft,
    call: () => Promise<GatewayResult>,
  ): Promise<string | undefined> {
    void draft;
    this.enforceAvailability();
    if (this.state.source === 'script') {
      return undefined;
    }
    let result: GatewayResult;
    try {
      result = await call();
    } catch {
      const error: GatewayError = {
        code: 'AI_UNAVAILABLE', retryable: true, requestId: '', message: 'AI 服务暂时不可用。',
      };
      this.state = { source: 'script', fallbackStep: this.state.fallbackStep, lastError: error };
      return undefined;
    }
    if (isFailure(result)) {
      const failure: GatewayFailure = result as GatewayFailure;
      this.state = {
        source: 'script',
        fallbackStep: this.state.fallbackStep,
        lastError: failure.error,
      };
      return undefined;
    }
    const success: GatewaySuccess = result as GatewaySuccess;
    const reply = conciseReply(success.text);
    if (reply === undefined) {
      const emptyError: GatewayError = {
        code: 'AI_UNAVAILABLE',
        retryable: true,
        requestId: success.requestId,
        message: 'AI 未返回可用的简短提示。',
      };
      this.state = {
        source: 'script',
        fallbackStep: this.state.fallbackStep,
        lastError: emptyError,
      };
      return undefined;
    }
    return reply;
  }

  private enforceAvailability(): void {
    if (!this.aiAvailable) {
      this.state.source = 'script';
      this.state.lastError = undefined;
    }
  }

  private assistantMessage(text: string): ChatMessage {
    return { role: 'ai', text: text, ts: Date.now() };
  }

  private withUserLine(draft: Draft, userText: string, ts: number): ChatMessage[] {
    const next: ChatMessage[] = [];
    for (let index = 0; index < draft.transcript.length; index += 1) {
      next.push(draft.transcript[index]);
    }
    next.push({ role: 'user', text: userText, ts: ts });
    return next;
  }

  private toSummary(draft: Draft, recentOnly: boolean = true): DraftSummaryExport {
    const summary: DraftSummaryExport = {
      mood: draft.mood,
      // Keep a recent context window within the gateway request limit.
      transcript: recentOnly ? draft.transcript.slice(-24) : draft.transcript.slice(),
    };
    if (draft.timeMark !== undefined) {
      summary.timeMark = draft.timeMark;
    }
    return summary;
  }
}

interface DraftSummaryExport {
  mood: MoodState;
  timeMark?: string;
  transcript: ChatMessage[];
}

function cloneDraftWith(draft: Draft, transcript: ChatMessage[]): Draft {
  const next: Draft = {
    mood: draft.mood,
    transcript: transcript,
    diaryEnabled: draft.diaryEnabled,
  };
  if (draft.kind !== undefined) next.kind = draft.kind;
  if (draft.timeMark !== undefined) next.timeMark = draft.timeMark;
  if (draft.note !== undefined) next.note = draft.note;
  if (draft.diary !== undefined) next.diary = draft.diary;
  if (draft.stickerTemplate !== undefined) next.stickerTemplate = draft.stickerTemplate;
  return next;
}

/** Choose one complete short sentence; never show a clipped paragraph. */
export function conciseReply(text: string): string | undefined {
  const cleaned = text.trim().replace(/[*_`#]/g, '');
  const sentences = cleaned.match(/[^。！？!?\n]+[。！？!?]?/g);
  if (sentences === null) return undefined;
  for (let index = 0; index < sentences.length; index += 1) {
    const sentence = sentences[index].trim();
    if (sentence.length <= 48 && /[？?]$/.test(sentence)) return sentence;
  }
  const first = sentences[0].trim();
  if (first.length > 0 && first.length <= 48) return first;
  return undefined;
}
