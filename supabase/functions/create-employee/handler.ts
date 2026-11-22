const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (status: number, code: string) => new Response(JSON.stringify({ code }), {
  status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});
type Config = { url: string; serviceKey: string };

export async function handleCreateEmployee(request: Request, config: Config, fetcher: typeof fetch = fetch): Promise<Response> {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') return reply(405, 'method_not_allowed');
  const authorization = request.headers.get('Authorization') ?? '';
  if (!/^Bearer \S+$/i.test(authorization)) return reply(401, 'unauthorized');
  if (!config.url || !config.serviceKey) return reply(503, 'not_configured');
  const adminHeaders = {
    apikey: config.serviceKey,
    Authorization: `Bearer ${config.serviceKey}`,
    'Content-Type': 'application/json',
  };
  try {
    // Verifico l’identità con Auth e non mi fido di un’identità dichiarata nel corpo.
    const auth = await fetcher(`${config.url}/auth/v1/user`, {
      headers: { apikey: config.serviceKey, Authorization: authorization },
    });
    if (!auth.ok) return reply(auth.status >= 500 ? 503 : 401, auth.status >= 500 ? 'unavailable' : 'unauthorized');
    const user = await auth.json();
    if (typeof user.id !== 'string') return reply(401, 'unauthorized');
    const query = new URLSearchParams({ id: `eq.${user.id}`, select: 'role,active' });
    const profileResponse = await fetcher(`${config.url}/rest/v1/user_profile?${query}`, { headers: adminHeaders });
    if (!profileResponse.ok) return reply(503, 'unavailable');
    const profiles = await profileResponse.json();
    if (!Array.isArray(profiles) || profiles.length !== 1 || profiles[0].role !== 'ADMIN' || profiles[0].active !== true) {
      return reply(403, 'forbidden');
    }
    // Limito il corpo anche senza Content-Length e non lo conservo né lo registro.
    const reader = request.body?.getReader();
    if (!reader) return reply(400, 'invalid_input');
    const chunks: Uint8Array[] = [];
    let length = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 8192) { await reader.cancel(); return reply(413, 'invalid_input'); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    let body;
    try { body = JSON.parse(new TextDecoder().decode(bytes)); }
    catch { return reply(400, 'invalid_input'); }
    if (!body || Array.isArray(body) || typeof body !== 'object' ||
        Object.keys(body).some((key) => !['first_name', 'last_name', 'email', 'password'].includes(key)) ||
        !['first_name', 'last_name', 'email', 'password'].every((key) => typeof body[key] === 'string')) {
      return reply(400, 'invalid_input');
    }
    const first = body.first_name.trim();
    const last = body.last_name.trim();
    const email = body.email.trim().toLowerCase();
    const password = body.password;
    if ([first, last].some((name) => [...name].length < 1 || [...name].length > 120) ||
        email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
        !password.trim() || [...password].length < 8 || new TextEncoder().encode(password).length > 72) {
      return reply(400, 'invalid_input');
    }
    const created = await fetcher(`${config.url}/auth/v1/admin/users`, {
      method: 'POST', headers: adminHeaders,
      body: JSON.stringify({
        email, password, email_confirm: true,
        // Passo i dati nei metadata amministrativi; affido al trigger la creazione del profilo.
        app_metadata: { shiftumc_employee: { first_name: first, last_name: last, created_by: user.id } },
      }),
    });
    if (!created.ok) {
      const error = await created.json().catch(() => ({}));
      const code = error.code ?? error.error_code;
      if (['email_exists', 'user_already_exists'].includes(code)) return reply(409, 'email_exists');
      if (code === 'weak_password') return reply(400, 'weak_password');
      return reply(502, 'creation_failed');
    }
    // Restituisco soltanto l’esito, senza credenziali, token o dati Auth.
    return reply(201, 'created');
  } catch {
    return reply(503, 'unavailable');
  }
}
