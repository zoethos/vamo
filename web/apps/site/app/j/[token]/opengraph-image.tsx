import { ImageResponse } from "next/og";
import { fetchTripPreview } from "../../../lib/trip-preview";
import { themeGradientCss } from "../../../lib/theme";

export const runtime = "edge";
export const dynamic = "force-dynamic";
export const revalidate = 0;
export const alt = "Vamo trip invite preview";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

type Props = {
  params: Promise<{ token: string }>;
};

export default async function OpenGraphImage({ params }: Props) {
  const { token } = await params;
  const preview = await fetchTripPreview(token);

  if (!preview) {
    return new ImageResponse(
      (
        <div
          style={{
            width: "100%",
            height: "100%",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            background: "#0F1126",
            color: "#FAFAFB",
            fontSize: 48,
            fontWeight: 700,
          }}
        >
          Vamo
        </div>
      ),
      size,
    );
  }

  const memberLabel =
    preview.memberCount === 1
      ? "1 Vamigo going"
      : `${preview.memberCount} Vamigos going`;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          background: themeGradientCss(preview.theme),
          color: "#FAFAFB",
          padding: 64,
          justifyContent: "space-between",
        }}
      >
        <div style={{ fontSize: 28, opacity: 0.9 }}>Vamo</div>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div style={{ fontSize: 64, fontWeight: 800, lineHeight: 1.05 }}>
            {preview.tripName}
          </div>
          {preview.destination ? (
            <div style={{ fontSize: 32, opacity: 0.92 }}>
              {preview.destination}
            </div>
          ) : null}
          <div style={{ fontSize: 28, opacity: 0.88 }}>{memberLabel}</div>
        </div>
        {preview.theme.tagline ? (
          <div style={{ fontSize: 32, fontWeight: 600 }}>
            {preview.theme.tagline}
          </div>
        ) : (
          <div style={{ fontSize: 28, opacity: 0.85 }}>Si va?</div>
        )}
      </div>
    ),
    size,
  );
}
