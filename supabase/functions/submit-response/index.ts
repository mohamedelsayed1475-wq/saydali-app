import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8"

// ── Allowed origins (update if you host the web portal elsewhere) ──
const ALLOWED_ORIGINS = [
  'https://saydali.app',
]

function getAllowedOrigin(req: Request): string {
  const origin = req.headers.get('Origin') ?? ''
  if (ALLOWED_ORIGINS.includes(origin)) return origin
  if (!origin) return '*'
  return ALLOWED_ORIGINS[0]
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getAllowedOrigin(req),
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  }
}

// ── Simple in-memory IP rate limiter ──────────────────────────────
// Limit: 10 submissions per IP per 60-second window (tighter than get-session)
const RATE_LIMIT = 10
const WINDOW_MS  = 60_000

const _ipMap = new Map<string, { count: number; resetAt: number }>()

function checkRateLimit(ip: string): boolean {
  const now   = Date.now()
  const entry = _ipMap.get(ip)

  if (!entry || now > entry.resetAt) {
    _ipMap.set(ip, { count: 1, resetAt: now + WINDOW_MS })
    return true
  }
  entry.count++
  if (entry.count > RATE_LIMIT) return false
  return true
}

function getClientIp(req: Request): string {
  return (
    req.headers.get('x-forwarded-for')?.split(',')[0].trim() ??
    req.headers.get('cf-connecting-ip') ??
    'unknown'
  )
}

// ── Generate an 8-character random response code ──────────────────
function generateCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  let result  = ''
  for (let i = 0; i < 8; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length))
  }
  return result
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders(req) })
  }

  // Only allow POST
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
    )
  }

  // Rate limiting
  const clientIp = getClientIp(req)
  if (!checkRateLimit(clientIp)) {
    return new Response(
      JSON.stringify({ error: 'Too many requests. Please wait a moment and try again.' }),
      { status: 429, headers: { ...corsHeaders(req), 'Content-Type': 'application/json', 'Retry-After': '60' } }
    )
  }

  try {
    const supabaseUrl        = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase           = createClient(supabaseUrl, supabaseServiceKey)

    let body: Record<string, unknown>
    try {
      body = await req.json()
    } catch {
      return new Response(
        JSON.stringify({ error: 'Invalid JSON body' }),
        { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    const { action } = body

    // ─── Action: Renew Session ───────────────────────────────────
    if (action === 'renew') {
      const session_code = (body.session_code as string | undefined)?.toUpperCase().trim()
      const rep_phone    = (body.rep_phone as string | undefined) ?? ''

      if (!session_code) {
        return new Response(
          JSON.stringify({ error: 'session_code is required for renewal' }),
          { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
        )
      }

      // Validate: code must be alphanumeric
      if (!/^[A-Z0-9]{4,12}$/.test(session_code)) {
        return new Response(
          JSON.stringify({ error: 'Invalid session code format' }),
          { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
        )
      }

      const { error: renewalError } = await supabase
        .from('renewal_requests')
        .insert({
          session_code: session_code,
          rep_phone:    rep_phone,
          requested_at: new Date().toISOString(),
          status:       'pending',
        })

      if (renewalError) throw renewalError

      return new Response(
        JSON.stringify({ ok: true }),
        { status: 200, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // ─── Action: Submit Responses ────────────────────────────────
    const session_id = body.session_id as string | undefined
    const responses  = body.responses as unknown[] | undefined

    if (!session_id || !responses || !Array.isArray(responses)) {
      return new Response(
        JSON.stringify({ error: 'session_id and responses array are required' }),
        { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // Validate session_id looks like a UUID
    if (!/^[0-9a-f-]{36}$/i.test(session_id)) {
      return new Response(
        JSON.stringify({ error: 'Invalid session_id format' }),
        { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // Guard: session must be in 'pending' state (prevent double-submit)
    const { data: sessionCheck, error: checkErr } = await supabase
      .from('rep_sessions')
      .select('id, status')
      .eq('id', session_id)
      .maybeSingle()

    if (checkErr) throw checkErr

    if (!sessionCheck) {
      return new Response(
        JSON.stringify({ error: 'Session not found' }),
        { status: 404, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    if (sessionCheck.status !== 'pending') {
      return new Response(
        JSON.stringify({ error: 'Session has already been responded or is invalid' }),
        { status: 409, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // 1. Update session items
    for (const r of responses as Record<string, unknown>[]) {
      const { error: itemError } = await supabase
        .from('session_items')
        .update({
          is_available:    r.is_available,
          quantity:        r.quantity,
          price:           r.price,
          discount:        r.discount,
          rep_notes:       r.rep_notes,
          rep_alternative: r.rep_alternative,
        })
        .eq('id', r.item_id)
        .eq('session_id', session_id)

      if (itemError) throw itemError
    }

    // 2. Update session status
    const { error: sessionError } = await supabase
      .from('rep_sessions')
      .update({
        status:       'responded',
        responded_at: new Date().toISOString(),
      })
      .eq('id', session_id)

    if (sessionError) throw sessionError

    // 3. Generate and store response code
    const responseCode = generateCode()
    const { error: codeError } = await supabase
      .from('response_codes')
      .insert({ response_code: responseCode, session_id: session_id })

    if (codeError) throw codeError

    return new Response(
      JSON.stringify({ response_code: responseCode }),
      { status: 200, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('submit-response error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
    )
  }
})
