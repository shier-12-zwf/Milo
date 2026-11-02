/**
 * Public contract shared with the HarmonyOS client. Keep this file free of
 * any MiniMax-specific symbols so the same shape can be re-used if the
 * transport is swapped later.
 */

export type MoodId =
  | 'very-low' | 'low' | 'heavy' | 'calm' | 'okay' | 'bright' | 'joyful'
  | 'lonely' | 'sad' | 'angry' | 'afraid' | 'disappointed'
  | 'anxious' | 'aggrieved' | 'embarrassed';

export type ChatRole = 'user' | 'ai';

export interface ChatMessage {
  role: ChatRole;
  text: string;
  ts: number;
}

export interface MoodState {
  valence: number;
  labels: string[];
  emotionId?: MoodId;
}

export interface DraftSummary {
  mood: MoodState;
  timeMark?: string;
  transcript: ChatMessage[];
}

export const MAX_TRANSCRIPT_LINES = 32;
export const MAX_TEXT_LENGTH = 2000;
export const MAX_LABELS = 6;
export const MAX_LABEL_LENGTH = 32;

export type ErrorCode =
  | 'AI_DISABLED'
  | 'AI_UNAVAILABLE'
  | 'RATE_LIMITED'
  | 'INVALID_REQUEST'
  | 'CONTENT_BLOCKED';

export interface ErrorEnvelope {
  code: ErrorCode;
  message: string;
  retryable: boolean;
  requestId: string;
}

export interface OpenRequest {
  draft: DraftSummary;
}

export interface OpenResponse {
  text: string;
  requestId: string;
}

export interface RespondRequest {
  draft: DraftSummary;
  userText: string;
}

export interface RespondResponse {
  text: string;
  requestId: string;
}

export interface DiaryRequest {
  draft: DraftSummary;
}

export interface DiaryResponse {
  text: string;
  requestId: string;
}

export interface HealthResponse {
  ok: boolean;
  aiEnabled: boolean;
  aiStatus: 'enabled' | 'paused';
  model: string;
  baseUrl: string;
  requestId: string;
}

export const VALID_MOOD_IDS: ReadonlyArray<MoodId> = [
  'very-low', 'low', 'heavy', 'calm', 'okay', 'bright', 'joyful',
  'lonely', 'sad', 'angry', 'afraid', 'disappointed',
  'anxious', 'aggrieved', 'embarrassed',
];

export function isValidMoodId(value: unknown): value is MoodId {
  if (typeof value !== 'string') return false;
  for (let index = 0; index < VALID_MOOD_IDS.length; index += 1) {
    if (VALID_MOOD_IDS[index] === value) return true;
  }
  return false;
}

export function isValidRole(value: unknown): value is ChatRole {
  return value === 'user' || value === 'ai';
}
