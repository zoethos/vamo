import { redirect } from "next/navigation";

export default function ConsoleHomePage() {
  redirect("/admin/ingestion");
}
