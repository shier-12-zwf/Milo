import { AI_FEATURE_AVAILABLE } from './aiAvailability.ts'

// Product availability takes precedence over the hosting-specific preference.
export const PUBLIC_AI_ENABLED = AI_FEATURE_AVAILABLE && import.meta.env.VITE_PUBLIC_AI_ENABLED !== 'false'
