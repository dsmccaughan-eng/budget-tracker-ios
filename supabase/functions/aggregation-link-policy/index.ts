import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { AuthError, requireUser } from "../_shared/auth.ts";
import { buildLinkPolicy } from "../_shared/connection-policy.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import {
  checkRateLimit,
  clientSafeError,
  securityHeaders,
} from "../_shared/security.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  try {
    const { admin, user } = await requireUser(req);
    if (!checkRateLimit(user.id, "aggregation-link-policy", 30)) {
      return jsonResponse({ error: "Rate limit exceeded. Try again shortly." }, 429);
    }

    const policy = await buildLinkPolicy(admin);
    return jsonResponse(policy, 200, securityHeaders);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonResponse({ error: error.message }, error.status, securityHeaders);
    }
    return jsonResponse({
      error: clientSafeError(error, "Unable to determine link provider."),
    }, 500, securityHeaders);
  }
});
