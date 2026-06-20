import type { APIRoute } from "astro";
import type { FeedCache } from "@/types";

export const GET: APIRoute = async () => {
	let cache: FeedCache = {};
	try {
		cache = (await import("@/feed-cache.json")).default;
	} catch {
		// not generated yet
	}

	interface PostWithMember {
		title: string;
		link: string;
		published: string;
		description?: string;
		author: string;
		website: string;
	}

	const allPosts: PostWithMember[] = [];

	for (const [website, memberData] of Object.entries(cache)) {
		for (const post of memberData.posts) {
			allPosts.push({
				title: post.title,
				link: post.link,
				published: post.published,
				description: post.description,
				author: memberData.name,
				website: memberData.website,
			});
		}
	}

	allPosts.sort(
		(a, b) =>
			new Date(b.published).getTime() - new Date(a.published).getTime(),
	);

	const escapeXml = (str: string) =>
		str
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;")
			.replace(/"/g, "&quot;")
			.replace(/'/g, "&apos;");

	const stripHtml = (html: string): string =>
		html.replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim();

	const items = allPosts
		.slice(0, 50)
		.map((post) => {
			const pubDate = new Date(post.published).toUTCString();
			const description = post.description
				? escapeXml(stripHtml(post.description))
				: "";
			return `    <item>
      <title>${escapeXml(post.title)}</title>
      <link>${escapeXml(post.link)}</link>
      <guid isPermaLink="true">${escapeXml(post.link)}</guid>
      <pubDate>${pubDate}</pubDate>
      <dc:creator>${escapeXml(post.author)}</dc:creator>
      ${description ? `<description>${description}</description>` : ""}
    </item>`;
		})
		.join("\n");

	const xml = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
     xmlns:dc="http://purl.org/dc/elements/1.1/"
     xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>amrita.town blogroll</title>
    <link>https://amrita.town/blogroll</link>
    <description>recent posts from the amrita.town webring</description>
    <language>en</language>
    <atom:link href="https://amrita.town/blogroll.xml" rel="self" type="application/rss+xml"/>
    <lastBuildDate>${new Date().toUTCString()}</lastBuildDate>
${items}
  </channel>
</rss>`;

	return new Response(xml, {
		headers: {
			"Content-Type": "application/rss+xml; charset=utf-8",
		},
	});
};