import type { APIRoute } from "astro";
import type { FeedCache } from "@/types";

export const GET: APIRoute = async () => {
	let cache: FeedCache = {};
	try {
		cache = (await import("@/feed-cache.json")).default;
	} catch {
		// not generated yet
	}

	const escapeXml = (str: string) =>
		str
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;")
			.replace(/"/g, "&quot;");

	const outlines = Object.values(cache)
		.filter((m) => m.feedUrls && m.feedUrls.length > 0)
		.map(
			(m) =>
				`    <outline text="${escapeXml(m.name)}" title="${escapeXml(m.name)}" htmlUrl="${escapeXml(`https://${m.website}`)}" xmlUrl="${escapeXml(m.feedUrls![0])}" />`,
		)
		.join("\n");

	const xml = `<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0">
  <head>
    <title>amrita.town blogroll</title>
  </head>
  <body>
${outlines}
  </body>
</opml>`;

	return new Response(xml, {
		headers: {
			"Content-Type": "text/x-opml; charset=utf-8",
			"Content-Disposition": 'attachment; filename="amrita-town-blogroll.opml"',
		},
	});
};