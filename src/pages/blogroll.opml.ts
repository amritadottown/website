import type { APIRoute } from "astro";
import sortedMembers from "@/sorted-members";

export const GET: APIRoute = async () => {
	const escapeXml = (str: string) =>
		str
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;")
			.replace(/"/g, "&quot;");

	// members.json is the source of truth for feed URLs (OPML lists feeds,
	// not posts, so feed-cache.json isn't needed here at all).
	const outlines = sortedMembers
		.filter((m) => m.feeds && m.feeds.length > 0)
		.map(
			(m) =>
				`    <outline text="${escapeXml(m.name)}" title="${escapeXml(m.name)}" htmlUrl="${escapeXml(`https://${m.website}`)}" xmlUrl="${escapeXml(m.feeds![0])}" />`,
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