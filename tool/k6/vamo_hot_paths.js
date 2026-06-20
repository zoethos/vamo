import http from 'k6/http';
import { check, fail, sleep } from 'k6';

const targetLabel = __ENV.K6_TARGET_LABEL;
const allowNonStaging = __ENV.K6_ALLOW_NON_STAGING === 'true';
const knownProdSupabaseRef = 'mjercplkmuoctdklosyy';

if (
  (!targetLabel || !targetLabel.toLowerCase().includes('staging')) &&
  !allowNonStaging
) {
  throw new Error(
    'Refusing to run: set K6_TARGET_LABEL=staging for the staging project, ' +
      'or set K6_ALLOW_NON_STAGING=true only for another intentional non-prod run.',
  );
}

const baseUrl = requireEnv('SUPABASE_URL').replace(/\/$/, '');
if (baseUrl.includes(knownProdSupabaseRef)) {
  throw new Error(
    'Refusing to run: SUPABASE_URL contains the known production project ref. ' +
      'The k6 script writes trips and expenses; use staging instead.',
  );
}
const anonKey = requireEnv('SUPABASE_ANON_KEY');
const userAEmail = __ENV.K6_USER_A_EMAIL || __ENV.RLS_USER_A_EMAIL;
const userAPassword = __ENV.K6_USER_A_PASSWORD || __ENV.RLS_USER_A_PASSWORD;
const userBEmail = __ENV.K6_USER_B_EMAIL || __ENV.RLS_USER_B_EMAIL;
const userBPassword = __ENV.K6_USER_B_PASSWORD || __ENV.RLS_USER_B_PASSWORD;

if (!userAEmail || !userAPassword || !userBEmail || !userBPassword) {
  throw new Error(
    'Missing K6_USER_A/B_EMAIL + K6_USER_A/B_PASSWORD ' +
      '(or RLS_USER_A/B_* fallbacks).',
  );
}

export const options = {
  scenarios: {
    hot_paths: {
      executor: 'constant-vus',
      vus: Number(__ENV.K6_VUS || 2),
      duration: __ENV.K6_DURATION || '1m',
      gracefulStop: '10s',
    },
  },
  thresholds: {
    checks: ['rate>0.95'],
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<1500', 'p(99)<3000'],
  },
};

export default function () {
  const runId = `${Date.now()}-${__VU}-${__ITER}`;
  const a = signIn(userAEmail, userAPassword);
  const b = signIn(userBEmail, userBPassword);
  const tripId = uuid();

  rpc(a.token, 'create_trip', {
    p_id: tripId,
    p_name: `k6 c2 ${runId}`,
    p_destination: 'Staging',
    p_start_date: new Date().toISOString().slice(0, 10),
    p_base_currency: 'EUR',
  });

  const invite = tableInsert(a.token, 'invites', {
    trip_id: tripId,
    created_by: a.userId,
  });
  const token = invite && invite.token;
  check(token, { 'invite token returned': (value) => Boolean(value) });

  const joinedTrip = rpc(b.token, 'join_trip', { p_token: token });
  check(joinedTrip, { 'join_trip returns trip id': (value) => value === tripId });

  const committedExpenseId = uuid();
  rpc(a.token, 'insert_committed_expense', {
    p_id: committedExpenseId,
    p_trip_id: tripId,
    p_payer_id: a.userId,
    p_amount_cents: 1200,
    p_currency: 'EUR',
    p_base_cents: 1200,
    p_fx_rate: 1,
    p_description: `k6 committed ${runId}`,
    p_category: 'food',
    p_shares: [],
  });

  const proposedExpenseId = uuid();
  rpc(b.token, 'propose_expense', {
    p_id: proposedExpenseId,
    p_trip_id: tripId,
    p_payer_id: b.userId,
    p_amount_cents: 900,
    p_currency: 'EUR',
    p_base_cents: 900,
    p_fx_rate: 1,
    p_description: `k6 proposed ${runId}`,
    p_category: 'transport',
  });

  rpc(a.token, 'commit_expense', { p_expense_id: proposedExpenseId });

  const expenses = tableSelect(b.token, 'expenses', `trip_id=eq.${tripId}`);
  check(expenses, {
    'B sees two expenses': (rows) => Array.isArray(rows) && rows.length === 2,
  });

  const balances = tableSelect(a.token, 'trip_balances', `trip_id=eq.${tripId}`);
  check(balances, {
    'balances sum to zero': (rows) =>
      Array.isArray(rows) &&
      rows.length === 2 &&
      rows.reduce((sum, row) => sum + row.net_cents, 0) === 0,
  });

  sleep(Number(__ENV.K6_ITER_SLEEP_SECONDS || 1));
}

function signIn(email, password) {
  const response = http.post(
    `${baseUrl}/auth/v1/token?grant_type=password`,
    JSON.stringify({ email, password }),
    {
      headers: {
        apikey: anonKey,
        'content-type': 'application/json',
      },
      tags: { name: 'auth_password' },
    },
  );
  check(response, { 'auth 200': (r) => r.status === 200 });
  if (response.status !== 200) {
    fail(`auth failed (${response.status}): ${response.body}`);
  }
  const body = response.json();
  return {
    token: body.access_token,
    userId: body.user.id,
  };
}

function rpc(token, name, params) {
  const response = http.post(
    `${baseUrl}/rest/v1/rpc/${name}`,
    JSON.stringify(params),
    { headers: authHeaders(token), tags: { name: `rpc_${name}` } },
  );
  check(response, { [`${name} 2xx`]: (r) => r.status >= 200 && r.status < 300 });
  if (response.status < 200 || response.status >= 300) {
    fail(`${name} failed (${response.status}): ${response.body}`);
  }
  return response.body ? response.json() : null;
}

function tableInsert(token, table, payload) {
  const response = http.post(
    `${baseUrl}/rest/v1/${table}?select=*`,
    JSON.stringify(payload),
    {
      headers: { ...authHeaders(token), Prefer: 'return=representation' },
      tags: { name: `insert_${table}` },
    },
  );
  check(response, {
    [`insert ${table} 201`]: (r) => r.status === 201 || r.status === 200,
  });
  if (response.status !== 201 && response.status !== 200) {
    fail(`insert ${table} failed (${response.status}): ${response.body}`);
  }
  const rows = response.json();
  return Array.isArray(rows) ? rows[0] : rows;
}

function tableSelect(token, table, query) {
  const response = http.get(`${baseUrl}/rest/v1/${table}?select=*&${query}`, {
    headers: authHeaders(token),
    tags: { name: `select_${table}` },
  });
  check(response, { [`select ${table} 200`]: (r) => r.status === 200 });
  if (response.status !== 200) {
    fail(`select ${table} failed (${response.status}): ${response.body}`);
  }
  return response.json();
}

function authHeaders(token) {
  return {
    apikey: anonKey,
    authorization: `Bearer ${token}`,
    'content-type': 'application/json',
  };
}

function requireEnv(name) {
  const value = __ENV[name];
  if (!value) throw new Error(`Missing env: ${name}`);
  return value;
}

function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (char) => {
    const rand = Math.floor(Math.random() * 16);
    const value = char === 'x' ? rand : (rand & 0x3) | 0x8;
    return value.toString(16);
  });
}
