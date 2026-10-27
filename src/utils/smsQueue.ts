/**
 * SMS Queue Utility
 * Queues SMS to Supabase for Raspberry Pi processing
 */

import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY

let supabase: ReturnType<typeof createClient> | null = null

if (supabaseUrl && supabaseKey) {
  supabase = createClient(supabaseUrl, supabaseKey)
}

type SMSQueueData = {
  id: string
  phone_number: string
  message: string
  type: string
  priority: number
  status: string
  created_at: string
}

export interface SMSQueueItem {
  phone_number: string
  message: string
  type: string // Allow any valid SMS type from database
  priority?: number
  related_id?: string
  trip_id?: string
}

/**
 * Queue SMS to Supabase for processing by Raspberry Pi
 */
export async function queueSMS(sms: SMSQueueItem): Promise<{ success: boolean; error?: string; id?: string }> {
  if (!supabase) {
    return { success: false, error: 'Supabase not configured' }
  }

  try {
    const insertData: any = {
      phone_number: sms.phone_number,
      message: sms.message,
      type: sms.type,
      priority: sms.priority || 5,
      related_id: sms.related_id,
      trip_id: sms.trip_id,
      status: 'pending'
    }

    const result = await supabase
      .from('sms_queue')
      .insert(insertData)
      .select()
      .single()

    const { data, error } = result as { data: SMSQueueData | null; error: any }

    if (error) {
      console.error('Failed to queue SMS:', error)
      return { success: false, error: error.message }
    }

    if (!data) {
      return { success: false, error: 'No data returned' }
    }

    console.log('SMS queued successfully:', data.id)
    return { success: true, id: data.id }
  } catch (e) {
    console.error('Error queuing SMS:', e)
    return { success: false, error: 'Unknown error' }
  }
}

/**
 * Queue card reservation confirmation SMS
 */
export async function queueCardReservationSMS(
  phone: string,
  name: string,
  reservationId: string,
  cardType: string,
  pickupTerminal: string
): Promise<{ success: boolean; error?: string }> {
  const message = `Dear ${name}, card reserved. ID: ${reservationId}. Pickup: ${pickupTerminal}. Pay P110. Approval within 1-2 days. CommutAI`

  return queueSMS({
    phone_number: phone,
    message,
    type: 'card_reserved',
    priority: 7
  })
}

/**
 * Queue emergency alert SMS
 */
export async function queueEmergencySMS(
  phoneNumbers: string[],
  message: string,
  location?: { lat: number; lng: number }
): Promise<{ success: boolean; error?: string }> {
  if (!supabase) {
    return { success: false, error: 'Supabase not configured' }
  }

  const locationText = location ? ` Location: ${location.lat}, ${location.lng}` : ''
  const fullMessage = `EMERGENCY: ${message}${locationText}`

  const results = await Promise.all(
    phoneNumbers.map(phone =>
      queueSMS({
        phone_number: phone,
        message: fullMessage,
        type: 'emergency',
        priority: 10
      })
    )
  )

  const failed = results.filter(r => !r.success)
  if (failed.length > 0) {
    return { success: false, error: `${failed.length} SMS failed to queue` }
  }

  return { success: true }
}

/**
 * Queue trip completion SMS
 */
export async function queueTripCompletionSMS(
  phone: string,
  passengerName: string,
  busNumber: string,
  route: string,
  fare: number,
  alightingStop: string
): Promise<{ success: boolean; error?: string }> {
  const message = `CommutAI: ${passengerName}, trip completed. Bus: ${busNumber}. Route: ${route}. Fare: P${fare}. Alighting: ${alightingStop}. Thank you!`

  return queueSMS({
    phone_number: phone,
    message,
    type: 'alighting',
    priority: 5
  })
}
