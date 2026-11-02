/** Temporary product switch. Restore here after the AI service is ready again. */
export const AI_AVAILABLE: boolean = false;

/** Stored preferences stay intact while the feature is unavailable. */
export function effectiveAiEnabled(preference: boolean): boolean {
  return AI_AVAILABLE && preference;
}
