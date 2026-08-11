# Custom Expense Split Promotion

Status: operator checklist for the editable committed-expense split migration.
This migration changes the server-side committed-expense write path. Promote it
to Staging first and to Production in the same release window.

Related policy: [MIGRATION_PROMOTION_POLICY.md](MIGRATION_PROMOTION_POLICY.md).

## Migration

Apply exactly this file, once, through the appropriate Supabase SQL Editor.
Do not use a linked Supabase CLI schema command while the migration ledger is
being reconciled.

```text
supabase/migrations/20260811130000_custom_expense_split.sql
```

## Staging promotion

1. Apply `supabase/migrations/20260811130000_custom_expense_split.sql` in
   Vamo Staging.
2. In the app, use a three-member test trip. Create and commit a EUR 100.00
   expense with the custom split `50.00 / 30.00 / 20.00`.
3. Read that expense back from `public.expense_shares`. Its `base_cents` must
   equal the sum of its shares, and the three share values must be exactly
   `5000`, `3000`, and `2000` cents. Do not infer this from the editor preview.

```sql
select
  e.id as expense_id,
  e.base_cents,
  sum(s.share_cents) as share_cents_total,
  array_agg(s.share_cents order by s.share_cents desc) as share_cents
from public.expenses e
join public.expense_shares s on s.expense_id = e.id
where e.id = '<staging-committed-expense-uuid>'::uuid
group by e.id, e.base_cents;
```

Expected: `base_cents = 10000`, `share_cents_total = 10000`, and
`share_cents = {5000,3000,2000}`.

### Staging rejection proof

The SQL Editor normally runs as the owner, so it must establish the member
session context before exercising the RPC. Otherwise `not authenticated`
proves only the first guard, not custom-share validation.

Use a current member of the same three-member Staging test trip as both
`<test-user-uuid>` and `<payer-user-uuid>`. Replace every UUID placeholder
with a valid UUID before running the block. The three payload members must be
the active members of that trip exactly once.

```sql
begin;

set local role authenticated;
select set_config('request.jwt.claim.sub', '<test-user-uuid>', true);
select auth.uid() as effective_test_user;
-- Must equal <test-user-uuid>. Stop if it does not.

do $$
declare
  expected_message constant text :=
    'sum(shares)=9999 must equal base_cents=10000';
begin
  begin
    perform public.insert_committed_expense(
      p_id := '<rejection-expense-uuid>'::uuid,
      p_trip_id := '<staging-test-trip-uuid>'::uuid,
      p_payer_id := '<payer-user-uuid>'::uuid,
      p_amount_cents := 10000,
      p_currency := 'EUR'::char(3),
      p_base_cents := 10000,
      p_fx_rate := 1,
      p_description := 'custom split rejection smoke',
      p_shares := jsonb_build_array(
        jsonb_build_object(
          'id', '<share-one-uuid>'::uuid,
          'user_id', '<member-one-uuid>'::uuid,
          'share_cents', 5000
        ),
        jsonb_build_object(
          'id', '<share-two-uuid>'::uuid,
          'user_id', '<member-two-uuid>'::uuid,
          'share_cents', 3000
        ),
        jsonb_build_object(
          'id', '<share-three-uuid>'::uuid,
          'user_id', '<member-three-uuid>'::uuid,
          'share_cents', 1999
        )
      )
    );
    raise exception 'custom split rejection smoke unexpectedly succeeded';
  exception
    when others then
      if sqlerrm <> expected_message then
        raise exception 'expected %, received %', expected_message, sqlerrm;
      end if;
  end;
end;
$$;

select not exists (
  select 1
  from public.expenses
  where id = '<rejection-expense-uuid>'::uuid
) as rejection_left_no_expense;
-- Must be true before completing the smoke.

rollback;
```

Any error other than `sum(shares)=9999 must equal base_cents=10000`, including
`not authenticated`, fails this smoke. The final `rollback` is mandatory and
the `rejection_left_no_expense` check must be true.

## Production promotion

Apply the same migration in Vamo Production only after every Staging check
above, including the rejection proof and cleanup, passes.

Use a dedicated Production smoke trip with three accounts controlled by the
team. Never create this expense in a real shared trip: committed expense data
changes member balances.

1. Apply `supabase/migrations/20260811130000_custom_expense_split.sql`.
2. In the app, commit EUR 100.00 with the `50.00 / 30.00 / 20.00` custom split.
3. Run the same read-back query, substituting its Production expense UUID.
   Expect `10000 = 10000` and `{5000,3000,2000}`.
4. Verify the dedicated smoke trip's established cleanup path before using it
   in Production; then clean up only that smoke-trip data.

## Promotion checkpoint

```text
Migration promotion checkpoint:
- Migration files changed: supabase/migrations/20260811130000_custom_expense_split.sql
- Staging project/ref:
- Staging apply status:
- Staging verification/read-back:
- Staging rejection proof and rollback cleanup:
- Production project/ref:
- Production apply status:
- Production verification/read-back:
- Production smoke-trip cleanup:
- Current drift:
- If production not promoted: blocker, owner, planned date, and why drift is acceptable:
- Environment-specific objects excluded from production: none
```
