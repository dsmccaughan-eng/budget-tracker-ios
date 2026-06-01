import { createClient, SupabaseClient, User } from "npm:@supabase/supabase-js@2";

export type AuthContext = {
  user: User;
  supabase: SupabaseClient;
  admin: SupabaseClient;
};

export async function requireUser(req: Request): Promise<AuthContext> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    throw new AuthError("Missing Authorization header", 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
    throw new AuthError("Server configuration error", 500);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    throw new AuthError("Invalid or expired session", 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  return { user, supabase, admin };
}

export class AuthError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}
