import { redirect } from "next/navigation";

function consoleUrl(): string {
  return process.env.CONFLUENDO_CONSOLE_URL?.trim() || "http://localhost:4373/admin/ingestion";
}

export default function AdminRedirectPage() {
  redirect(consoleUrl());
}
