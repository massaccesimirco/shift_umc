import { handleCreateEmployee } from './handler.ts';
const config = { url: 'https://example.invalid', serviceKey: 'server-secret' };
const input = { first_name: ' Anna ', last_name: ' Verdi ', email: ' ANNA@example.invalid ', password: 'password-test' };
const assert = (value: unknown) => { if (!value) throw new Error('Assertion failed'); };
function setup(options: { role?: string; active?: boolean; missing?: boolean; authStatus?: number; createStatus?: number; createCode?: string } = {}) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const fetcher: typeof fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith('/auth/v1/user')) return Response.json({ id: 'admin-id' }, { status: options.authStatus ?? 200 });
    if (String(url).includes('/rest/v1/user_profile')) return Response.json(options.missing ? [] : [{ role: options.role ?? 'ADMIN', active: options.active ?? true }]);
    return Response.json({ id: 'new-id', code: options.createCode }, { status: options.createStatus ?? 201 });
  };
  const request = (body: unknown = input, token = 'Bearer user-token') => new Request(config.url, { method: 'POST', headers: { Authorization: token }, body: JSON.stringify(body) });
  return { calls, fetcher, request };
}
Deno.test('Preflight e metodi: nessuna operazione Auth', async () => {
  const s = setup();
  assert((await handleCreateEmployee(new Request(config.url, { method: 'OPTIONS' }), config, s.fetcher)).status === 204);
  assert((await handleCreateEmployee(new Request(config.url), config, s.fetcher)).status === 405);
  assert(s.calls.length === 0);
});
Deno.test('Token assente o non valido: nessuna creazione', async () => {
  const s = setup({ authStatus: 401 });
  assert((await handleCreateEmployee(s.request(input, ''), config, s.fetcher)).status === 401);
  assert(s.calls.length === 0);
  assert((await handleCreateEmployee(s.request(), config, s.fetcher)).status === 401);
  assert(s.calls.length === 1);
});
Deno.test('Dipendente, admin inattivo e profilo mancante respinti', async () => {
  for (const option of [{ role: 'EMPLOYEE' }, { active: false }, { missing: true }]) {
    const s = setup(option);
    assert((await handleCreateEmployee(s.request(), config, s.fetcher)).status === 403);
    assert(s.calls.length === 2);
  }
});
Deno.test('Campi invalidi e tentativo di imporre ruolo/identità respinti', async () => {
  for (const body of [null, { ...input, role: 'ADMIN' }, { ...input, created_by: 'other' }, { ...input, first_name: '' }, { ...input, password: 'short' }, { ...input, password: 'x'.repeat(73) }, { ...input, password: '😀'.repeat(19) }, { ...input, email: 'no' }, { ...input, last_name: 'x'.repeat(121) }]) {
    const s = setup();
    assert((await handleCreateEmployee(s.request(body), config, s.fetcher)).status === 400);
    assert(s.calls.length === 2);
  }
});
Deno.test('Creazione: identità verificata, payload normalizzato, risposta senza segreti', async () => {
  const s = setup();
  const response = await handleCreateEmployee(s.request(), config, s.fetcher);
  assert(response.status === 201);
  const headers = s.calls[0].init!.headers as Record<string, string>;
  assert(headers.Authorization === 'Bearer user-token');
  const body = JSON.parse(s.calls[2].init!.body as string);
  assert(body.email === 'anna@example.invalid' && body.password === input.password);
  assert(body.app_metadata.shiftumc_employee.created_by === 'admin-id');
  assert(body.app_metadata.shiftumc_employee.first_name === 'Anna');
  assert(body.email_confirm === true && !body.role);
  assert(await response.text() === '{"code":"created"}');
});
Deno.test('Email duplicata, password debole e fallimento database restano errori', async () => {
  for (const [code, expected] of [['email_exists', 409], ['weak_password', 400], ['unexpected_failure', 502]] as const) {
    const s = setup({ createStatus: 422, createCode: code });
    assert((await handleCreateEmployee(s.request(), config, s.fetcher)).status === expected);
  }
});
Deno.test('Body troppo grande o JSON invalido non raggiungono creazione', async () => {
  const s = setup();
  assert((await handleCreateEmployee(s.request({ ...input, first_name: 'x'.repeat(9000) }), config, s.fetcher)).status === 413);
  const request = new Request(config.url, { method: 'POST', headers: { Authorization: 'Bearer token' }, body: '{' });
  assert((await handleCreateEmployee(request, config, s.fetcher)).status === 400);
  assert(s.calls.length === 4);
});
Deno.test('Errore di rete non restituisce dettagli del servizio', async () => {
  const s = setup();
  const response = await handleCreateEmployee(s.request(), config, () => { throw new Error('private-secret'); });
  assert(response.status === 503);
  assert(!(await response.text()).includes('private-secret'));
});
