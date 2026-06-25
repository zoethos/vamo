import {
  assertEquals,
} from "jsr:@std/assert@1.0.19";
import {
  isSoftCloseEligible,
  shouldNotifyWrappedTrip,
} from "./soft_close_sweep.ts";

Deno.test("isSoftCloseEligible requires active ended trip without reopen", () => {
  const today = "2026-06-05";
  assertEquals(
    isSoftCloseEligible(
      { lifecycle: "active", end_date: "2026-06-04", reopened_at: null },
      today,
    ),
    true,
  );
  assertEquals(
    isSoftCloseEligible(
      { lifecycle: "active", end_date: "2026-06-06", reopened_at: null },
      today,
    ),
    false,
  );
  assertEquals(
    isSoftCloseEligible(
      { lifecycle: "active", end_date: null, reopened_at: null },
      today,
    ),
    false,
  );
  assertEquals(
    isSoftCloseEligible(
      {
        lifecycle: "active",
        end_date: "2026-06-01",
        reopened_at: "2026-06-02T00:00:00Z",
      },
      today,
    ),
    false,
  );
  assertEquals(
    isSoftCloseEligible(
      { lifecycle: "soft_closed", end_date: "2026-06-01", reopened_at: null },
      today,
    ),
    false,
  );
});

Deno.test("shouldNotifyWrappedTrip recent vs old end dates", () => {
  const today = "2026-06-05";
  assertEquals(shouldNotifyWrappedTrip("2026-06-05", today), true);
  assertEquals(shouldNotifyWrappedTrip("2026-06-04", today), true);
  assertEquals(shouldNotifyWrappedTrip("2026-06-03", today), true);
  assertEquals(shouldNotifyWrappedTrip("2026-06-02", today), false);
  assertEquals(shouldNotifyWrappedTrip("2026-06-01", today), false);
});
