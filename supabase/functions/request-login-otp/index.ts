import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const PROJECT_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/** Comma-separated allowlist until SMTP is configured (e.g. OTP_ALLOWLIST=you@example.com). */
const ALLOWED_EMAILS = new Set(
  (Deno.env.get("OTP_ALLOWLIST") ?? "dsmccaughan@gmail.com")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean),
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  let email = "";
  try {
    const body = await req.json();
    email = String(body?.email ?? "").trim().toLowerCase();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!email || !email.includes("@")) {
    return json({ error: "Valid email required" }, 400);
  }

  if (!ALLOWED_EMAILS.has(email)) {
    return json({ error: "Email not authorized for sign-in" }, 403);
  }

  const linkRes = await fetch(`${PROJECT_URL}/auth/v1/admin/generate_link`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE,
      Authorization: `Bearer ${SERVICE_ROLE}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "magiclink", email }),
  });

  const linkText = await linkRes.text();
  if (!linkRes.ok) {
    console.error("generate_link failed", linkRes.status, linkText);
    return json({ error: "Could not create sign-in code" }, 500);
  }

  let payload: { email_otp?: string };
  try {
    payload = JSON.parse(linkText);
  } catch {
    return json({ error: "Invalid auth response" }, 500);
  }

  const otp = payload.email_otp?.trim();
  if (!otp) {
    return json({ error: "No sign-in code returned" }, 500);
  }

  return json({
    ok: true,
    otp,
    delivery: "in_app",
    message: "Use the sign-in code shown in the app.",
  });
});

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
