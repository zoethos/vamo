export interface RecordNotificationArgs {
  userId: string;
  tripId: string | null;
  type: string;
  title: string;
  body: string;
  route: string;
}

interface NotificationRpcClient {
  rpc(
    functionName: "record_notification",
    params: {
      p_user_id: string;
      p_trip_id: string | null;
      p_type: string;
      p_title: string;
      p_body: string;
      p_route: string;
    },
  ): PromiseLike<{ data: unknown; error: unknown }>;
}

/** Returns true when a durable notice row was created (lifecycle stamps key off this). */
export function shouldStampAfterRecord(recordId: string | null): boolean {
  return recordId != null;
}

export async function recordNotification(
  supabase: NotificationRpcClient,
  args: RecordNotificationArgs,
): Promise<string | null> {
  const { data, error } = await supabase.rpc("record_notification", {
    p_user_id: args.userId,
    p_trip_id: args.tripId,
    p_type: args.type,
    p_title: args.title,
    p_body: args.body,
    p_route: args.route,
  });
  if (error) {
    console.error("record_notification failed", error);
    return null;
  }
  return data as string;
}
