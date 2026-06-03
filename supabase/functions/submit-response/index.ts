import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Generate an 8-character random code
function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  let result = ''
  for (let i = 0; i < 8; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length))
  }
  return result
}

Deno.serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const body = await req.json()
    const { action } = body

    if (action === 'renew') {
      // ─── Action: Renew Session ───
      const { session_code, rep_phone } = body

      if (!session_code) {
        return new Response(
          JSON.stringify({ error: 'session_code is required for renewal' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const { error: renewalError } = await supabase
        .from('renewal_requests')
        .insert({
          session_code: session_code.toUpperCase(),
          rep_phone: rep_phone || '',
          requested_at: new Date().toISOString(),
          status: 'pending'
        })

      if (renewalError) throw renewalError

      return new Response(
        JSON.stringify({ ok: true }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ─── Action: Submit Responses ───
    const { session_id, responses } = body

    if (!session_id || !responses || !Array.isArray(responses)) {
      return new Response(
        JSON.stringify({ error: 'session_id and responses array are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 1. Update session items
    for (const r of responses) {
      const { error: itemError } = await supabase
        .from('session_items')
        .update({
          is_available: r.is_available,
          quantity: r.quantity,
          price: r.price,
          discount: r.discount,
          rep_notes: r.rep_notes,
          rep_alternative: r.rep_alternative
        })
        .eq('id', r.item_id)
        .eq('session_id', session_id)

      if (itemError) throw itemError
    }

    // 2. Update session status
    const { error: sessionError } = await supabase
      .from('rep_sessions')
      .update({
        status: 'responded',
        responded_at: new Date().toISOString()
      })
      .eq('id', session_id)

    if (sessionError) throw sessionError

    // 3. Generate response code
    const responseCode = generateCode()

    // 4. Insert response code
    const { error: codeError } = await supabase
      .from('response_codes')
      .insert({
        response_code: responseCode,
        session_id: session_id
      })

    if (codeError) throw codeError

    return new Response(
      JSON.stringify({ response_code: responseCode }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
