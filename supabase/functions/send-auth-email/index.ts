import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const FROM_EMAIL = Deno.env.get("AUTH_FROM_EMAIL") ?? "Budget Tracker <onboarding@resend.dev>";

type HookPayload = {
  user: { email: string };
  email_data: {
    token: string;
    email_action_type: string;
  };
};

function subjectFor(action: string): string {
  switch (action) {
    case "magiclink":
      return "Your Budget Tracker sign-in code";
    case "signup":
      return "Confirm your Budget Tracker signup";
    default:
      return "Budget Tracker verification code";
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  if (!RESEND_API_KEY) {
    return new Response(
      JSON.stringify({
        error: { message: "RESEND_API_KEY is not configured on the edge function" },
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const hookSecret = Deno.env.get("SEND_EMAIL_HOOK_SECRET");
  if (!hookSecret) {
    return new Response(
      JSON.stringify({
        error: { message: "SEND_EMAIL_HOOK_SECRET is not configured" },
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const payloadText = await req.text();
  const headers = Object.fromEntries(req.headers);
  const base64Secret = hookSecret.replace("v1,whsec_", "");
  const wh = new Webhook(base64Secret);

  let payload: HookPayload;
  try {
    payload = wh.verify(payloadText, headers) as HookPayload;
  } catch {
    return new Response(
      JSON.stringify({ error: { message: "Invalid send-email hook signature" } }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const { user, email_data } = payload;
  const token = email_data.token;
  const action = email_data.email_action_type;
  const subject = subjectFor(action);

  const html = `
    <h2>Your sign-in code</h2>
    <p>Enter this code in Budget Tracker:</p>
    <p style="font-size:32px;font-weight:bold;letter-spacing:6px">${token}</p>
    <p>This code expires soon. If you did not request it, you can ignore this email.</p>
  `;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [user.email],
      subject,
      html,
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    console.error("Resend error", res.status, errText);
    return new Response(
      JSON.stringify({
        error: {
          http_code: res.status,
          message: `Resend failed: ${errText.slice(0, 200)}`,
        },
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(JSON.stringify({}), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
