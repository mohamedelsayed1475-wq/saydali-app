import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const owner = 'mohamedelsayed1475-wq'
const repo = 'saydali-app'
const path = 'activation_codes.txt'
const apiBase = 'https://api.github.com'

// Simple memory rate-limiter
const ipCache = new Map<string, { count: number; lastRequest: number }>()
const RATE_LIMIT_WINDOW = 60000 // 1 minute
const MAX_REQUESTS = 5 // max 5 requests per minute for activation

function isRateLimited(ip: string): boolean {
  const now = Date.now()
  const record = ipCache.get(ip)
  if (!record) {
    ipCache.set(ip, { count: 1, lastRequest: now })
    return false
  }
  if (now - record.lastRequest > RATE_LIMIT_WINDOW) {
    ipCache.set(ip, { count: 1, lastRequest: now })
    return false
  }
  if (record.count >= MAX_REQUESTS) {
    return true
  }
  record.count++
  return false
}

Deno.serve(async (req, connInfo) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Rate Limiting
  const ip = req.headers.get('x-forwarded-for') || connInfo.remoteAddr?.hostname || 'unknown'
  if (isRateLimited(ip)) {
    return new Response(
      JSON.stringify({ success: false, error: 'لقد تجاوزت حد محاولات التفعيل. يرجى الانتظار دقيقة والمحاولة مجدداً.' }),
      { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  try {
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ success: false, error: 'Method not allowed' }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { code } = await req.json()
    if (!code || typeof code !== 'string') {
      return new Response(
        JSON.stringify({ success: false, error: 'يرجى إدخال كود تفعيل صحيح' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const cleanedCode = code.trim()

    // 1. Check if the database has an activation_codes table
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    try {
      // Try to check in local database table first (resilient design)
      const { data: dbCode, error: dbError } = await supabase
        .from('activation_codes')
        .select('*')
        .eq('code', cleanedCode)
        .eq('is_used', false)
        .maybeSingle()

      if (!dbError && dbCode) {
        // Mark code as used in the database
        const { error: updateError } = await supabase
          .from('activation_codes')
          .update({ is_used: true, used_at: new Date().toISOString() })
          .eq('code', cleanedCode)

        if (!updateError) {
          return new Response(
            JSON.stringify({ success: true }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
      }
    } catch (_) {
      // Table doesn't exist or other db error; fallback to GitHub raw flow
    }

    // 2. Fallback to GitHub file verification
    const pat = Deno.env.get('GITHUB_PAT')
    if (!pat) {
      return new Response(
        JSON.stringify({ success: false, error: 'خادم التفعيل غير مهيأ بعد (رمز GITHUB_PAT مفقود)' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // A. Fetch current file
    const getResp = await fetch(`${apiBase}/repos/${owner}/${repo}/contents/${path}`, {
      headers: {
        'Authorization': `Bearer ${pat}`,
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'SaydaliPro-Activation-Service',
      }
    })

    if (getResp.status !== 200) {
      return new Response(
        JSON.stringify({ success: false, error: 'فشل جلب أكواد التفعيل من خادم المطور' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const jsonData = await getResp.json()
    const sha = jsonData.sha
    const rawContent = atob(jsonData.content.replace(/\n/g, ''))

    const codes = rawContent
      .split('\n')
      .map((c: string) => c.trim())
      .filter((c: string) => c.length > 0)

    if (!codes.includes(cleanedCode)) {
      return new Response(
        JSON.stringify({ success: false, error: 'كود التفعيل غير صالح أو تم استخدامه من قبل' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // B. Code is valid! Remove it and commit back
    const updatedCodes = codes.filter((c: string) => c !== cleanedCode)
    const updatedContent = btoa(updatedCodes.join('\n'))

    const putResp = await fetch(`${apiBase}/repos/${owner}/${repo}/contents/${path}`, {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${pat}`,
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': 'SaydaliPro-Activation-Service',
      },
      body: JSON.stringify({
        message: 'chore: revoke used activation code',
        content: updatedContent,
        sha: sha,
      })
    })

    if (putResp.status !== 200 && putResp.status !== 201) {
      return new Response(
        JSON.stringify({ success: false, error: 'فشل تحديث خادم التفعيل' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
