/**
 * SMS Queue Utility
 * Functions for queuing SMS messages to Supabase
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Supabase URL and Anon Key must be configured')
}

const supabase: SupabaseClient = createClient(supabaseUrl, supabaseAnonKey)

export type SMSType = 'emergency' | 'alighting' | 'other'

export interface SMSQueueMessage {
  phone_number: string
  message: string
  type: SMSType
  priority?: number
  related_id?: string
  trip_id?: string
}

/**
 * Queue an SMS message to be sent by the Raspberry Pi processor
 */
export async function queueSMS(message: SMSQueueMessage): Promise<{ success: boolean; error?: string; data?: any }> {
  try {
    const { data, error } = await supabase
      .from('sms_queue')
      .insert({
        phone_number: message.phone_number,
        message: message.message,
        type: message.type,
        priority: message.priority || (message.type === 'emergency' ? 10 : 5),
        related_id: message.related_id,
        trip_id: message.trip_id,
        status: 'pending'
      })
      .select()
      .single()

    if (error) {
      console.error('Failed to queue SMS:', error)
      return { success: false, error: error.message }
    }

    console.log('SMS queued successfully:', data)
    return { success: true, data }
  } catch (error) {
    console.error('Error queuing SMS:', error)
    return { success: false, error: error instanceof Error ? error.message : 'Unknown error' }
  }
}

/**
 * Send an emergency alert SMS
 */
export async function sendEmergencyAlert(phoneNumber: string, location: string, details?: string): Promise<{ success: boolean; error?: string }> {
  const message = details
    ? `EMERGENCY ALERT: CommutAI bus needs assistance at ${location}. ${details}. Please respond immediately.`
    : `EMERGENCY ALERT: CommutAI bus needs assistance at ${location}. Please respond immediately.`

  return queueSMS({
    phone_number: phoneNumber,
    message,
    type: 'emergency',
    priority: 10
  })
}

/**
 * Send an alighting notification SMS
 */
export async function sendAlightingNotification(phoneNumber: string, stopName: string, etaMinutes?: number): Promise<{ success: boolean; error?: string }> {
  const message = etaMinutes
    ? `Your bus is approaching ${stopName} in approximately ${etaMinutes} minutes. Please prepare to alight.`
    : `Your bus is approaching ${stopName}. Please prepare to alight.`

  return queueSMS({
    phone_number: phoneNumber,
    message,
    type: 'alighting',
    priority: 5
  })
}

/**
 * Send a general notification SMS
 */
export async function sendNotificationSMS(phoneNumber: string, message: string): Promise<{ success: boolean; error?: string }> {
  return queueSMS({
    phone_number: phoneNumber,
    message,
    type: 'other',
    priority: 3
  })
}

/**
 * Queue multiple SMS messages in batch
 */
export async function queueSMSBatch(messages: SMSQueueMessage[]): Promise<{ success: boolean; errors: string[] }> {
  const errors: string[] = []

  for (const msg of messages) {
    const result = await queueSMS(msg)
    if (!result.success) {
      errors.push(`${msg.phone_number}: ${result.error}`)
    }
  }

  return {
    success: errors.length === 0,
    errors
  }
}

/**
 * Validate phone number format (basic validation)
 */
export function validatePhoneNumber(phoneNumber: string): boolean {
  // Remove spaces, dashes, and parentheses
  const cleaned = phoneNumber.replace(/[\s\-\(\)]/g, '')

  // Check if it starts with + and has 10-15 digits
  const phoneRegex = /^\+?[1-9]\d{9,14}$/

  return phoneRegex.test(cleaned)
}

/**
 * Format phone number to international format
 */
export function formatPhoneNumber(phoneNumber: string, countryCode: string = '+63'): string {
  const cleaned = phoneNumber.replace(/[\s\-\(\)]/g, '')

  // If already has country code, return as is
  if (cleaned.startsWith('+')) {
    return cleaned
  }

  // If starts with 0, replace with country code
  if (cleaned.startsWith('0')) {
    return countryCode + cleaned.substring(1)
  }

  // Otherwise, add country code
  return countryCode + cleaned
}
