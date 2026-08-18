import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8"

// ── Allowed origins (update if you host the web portal elsewhere) ──
const ALLOWED_ORIGINS = [
  'https://saydali.app',
]

function getAllowedOrigin(req: Request): string {
  const origin = req.headers.get('Origin') ?? ''
  if (ALLOWED_ORIGINS.includes(origin)) return origin
  // During local Supabase dev the origin is empty — allow it
  if (!origin) return '*'
  return ALLOWED_ORIGINS[0] // default: reflect first allowed origin
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getAllowedOrigin(req),
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  }
}

// ── Simple in-memory IP rate limiter ──────────────────────────────
// Limit: 30 requests per IP per 60-second window
const RATE_LIMIT = 30
const WINDOW_MS  = 60_000

const _ipMap = new Map<string, { count: number; resetAt: number }>()

function checkRateLimit(ip: string): boolean {
  const now   = Date.now()
  const entry = _ipMap.get(ip)

  if (!entry || now > entry.resetAt) {
    _ipMap.set(ip, { count: 1, resetAt: now + WINDOW_MS })
    return true // allowed
  }
  entry.count++
  if (entry.count > RATE_LIMIT) return false // blocked
  return true
}

function getClientIp(req: Request): string {
  return (
    req.headers.get('x-forwarded-for')?.split(',')[0].trim() ??
    req.headers.get('cf-connecting-ip') ??
    'unknown'
  )
}

Deno.serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders(req) })
  }

  // Only allow GET
  if (req.method !== 'GET') {
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
    const url  = new URL(req.url)
    const code = url.searchParams.get('code')?.trim().toUpperCase()

    if (!code) {
      return new Response(
        JSON.stringify({ error: 'Code parameter is required' }),
        { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // Basic format validation: 4–12 alphanumeric characters
    if (!/^[A-Z0-9]{4,12}$/.test(code)) {
      return new Response(
        JSON.stringify({ error: 'Invalid session code format' }),
        { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    const supabaseUrl        = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase           = createClient(supabaseUrl, supabaseServiceKey)

    // 1. Get session
    const { data: sessionData, error: sessionError } = await supabase
      .from('rep_sessions')
      .select('*')
      .eq('session_code', code)
      .maybeSingle()

    if (sessionError) throw sessionError

    if (!sessionData) {
      return new Response(
        JSON.stringify({ error: 'Session not found' }),
        { status: 404, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
      )
    }

    // 2. Get items (non-private)
    const { data: itemsData, error: itemsError } = await supabase
      .from('session_items')
      .select('*')
      .eq('session_id', sessionData.id)
      .eq('is_private', 0)

    if (itemsError) throw itemsError

    // 3. Get response code if responded
    let responseCode = null
    if (sessionData.status === 'responded') {
      const { data: codeData } = await supabase
        .from('response_codes')
        .select('response_code')
        .eq('session_id', sessionData.id)
        .maybeSingle()

      if (codeData) responseCode = codeData.response_code
    }

    return new Response(
      JSON.stringify({
        session:       sessionData,
        items:         itemsData || [],
        response_code: responseCode,
      }),
      { status: 200, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('get-session error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } }
    )
  }
})
