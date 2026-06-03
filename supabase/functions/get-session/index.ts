import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = new URL(req.url)
    const code = url.searchParams.get('code')?.trim().toUpperCase()

    if (!code) {
      return new Response(
        JSON.stringify({ error: 'Code parameter is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // 1. Get session
    const { data: sessionData, error: sessionError } = await supabase
      .from('rep_sessions')
      .select('*')
      .eq('session_code', code)
      .maybeSingle()

    if (sessionError) {
      throw sessionError
    }

    if (!sessionData) {
      return new Response(
        JSON.stringify({ error: 'Session not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Get items (non-private)
    const { data: itemsData, error: itemsError } = await supabase
      .from('session_items')
      .select('*')
      .eq('session_id', sessionData.id)
      .eq('is_private', 0)

    if (itemsError) {
      throw itemsError
    }

    // 3. Get response code if responded
    let responseCode = null
    if (sessionData.status === 'responded') {
      const { data: codeData } = await supabase
        .from('response_codes')
        .select('response_code')
        .eq('session_id', sessionData.id)
        .maybeSingle()
      
      if (codeData) {
        responseCode = codeData.response_code
      }
    }

    return new Response(
      JSON.stringify({
        session: sessionData,
        items: itemsData || [],
        response_code: responseCode
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
