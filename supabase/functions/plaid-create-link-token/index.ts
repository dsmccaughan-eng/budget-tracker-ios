import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { createPlaidLinkToken } from "../_shared/plaid-link.ts";
import {
  checkRateLimit,
  clientSafeError,
  securityHeaders,
} from "../_shared/security.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { user } = await requireUser(req);
    if (!checkRateLimit(user.id, "plaid-create-link-token", 10)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const payload = await createPlaidLinkToken({ userId: user.id });

    return jsonResponse({
      link_token: payload.link_token,
      expiration: payload.expiration,
    }, 200, securityHeaders);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonResponse({ error: error.message }, error.status, securityHeaders);
    }
    return jsonResponse({
      error: clientSafeError(error, "Unable to start bank link."),
    }, 500, securityHeaders);
  }
});
