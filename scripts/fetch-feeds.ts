import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { XMLParser } from "fast-xml-parser";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONCURRENCY_LIMIT = 5;
const FETCH_TIMEOUT_MS = 10_000;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Member {
	name: string;
	website: string;
	branch: string;
	campus: string;
	batch: string;
	feeds?: string[];
}

interface FeedPost {
	title: string;
	link: string;
	published: string; // ISO-8601
	description?: string;
}

interface MemberFeedCache {
	name: string;
	website: string;
	posts: FeedPost[];
}

type FeedCache = Record<string, MemberFeedCache>;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function fetchWithTimeout(
	url: string,
	timeout = FETCH_TIMEOUT_MS,
): Promise<Response> {
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), timeout);
	try {
		const res = await fetch(url, {
			signal: controller.signal,
			headers: { "User-Agent": "amrita.town-blogroll/1.0" },
		});
		return res;
	} finally {
		clearTimeout(timer);
	}
}

/** Resolve a possibly-relative URL against a base. */
function resolveUrl(href: string, base: string): string {
	try {
		return new URL(href, base).href;
	} catch {
		return href;
	}
}

// ---------------------------------------------------------------------------
// Feed auto-discovery
// ---------------------------------------------------------------------------

const COMMON_FEED_PATHS = [
	"/feed.xml",
	"/feed",
	"/rss.xml",
	"/rss",
	"/atom.xml",
	"/index.xml",
	"/blog/feed.xml",
	"/blog/feed",
	"/blog/rss.xml",
];

/**
 * Auto-discover feed URLs from a member's website by:
 * 1. Parsing <link> tags in the HTML
 * 2. Probing common feed paths
 */
async function discoverFeeds(website: string): Promise<string[]> {
	const rootDomain = website.startsWith("http")
		? new URL(website).hostname
		: website.split("/")[0];
	const baseUrl = `https://${website}`;
	const found = new Set<string>();

	// Try parsing HTML for <link> tags
	try {
		const res = await fetchWithTimeout(baseUrl);
		if (res.ok) {
			const html = await res.text();
			// Match <link rel="alternate" type="application/rss+xml" href="...">
			const linkRegex =
				/<link[^>]*?(?:rel=["']alternate["'][^>]*?type=["']application\/(?:rss|atom)\+xml["'][^>]*?href=["']([^"']+)["']|href=["']([^"']+)["'][^>]*?type=["']application\/(?:rss|atom)\+xml["'][^>]*?rel=["']alternate["'])/gi;
			let match: RegExpExecArray | null;
			while ((match = linkRegex.exec(html)) !== null) {
				const href = (match[1] || match[2])?.trim();
				if (href) found.add(resolveUrl(href, baseUrl));
			}
		}
	} catch {
		// silently continue
	}

	// Probe common feed paths
	for (const feedPath of COMMON_FEED_PATHS) {
		if (found.size >= 3) break; // limit to 3
		const url = `https://${rootDomain}${feedPath}`;
		if (found.has(url)) continue;
		try {
			const res = await fetchWithTimeout(url);
			if (res.ok) {
				const text = await res.text();
				const ct = res.headers.get("content-type") ?? "";
				if (
					ct.includes("xml") ||
					text.trim().startsWith("<?xml") ||
					text.includes("<rss") ||
					text.includes("<feed")
				) {
					found.add(url);
				}
			}
		} catch {
			// silently continue
		}
	}

	return [...found];
}

// ---------------------------------------------------------------------------
// Feed parsing (RSS 2.0 + Atom)
// ---------------------------------------------------------------------------

const parser = new XMLParser({
	ignoreAttributes: false,
	attributeNamePrefix: "@_",
	textNodeName: "#text",
	removeNSPrefix: true,
});

interface ParsedItem {
	title?: string;
	link?: string | { "@_href"?: string; "#text"?: string };
	pubDate?: string;
	published?: string;
	updated?: string;
	description?: string | { "#text"?: string };
	summary?: string | { "#text"?: string };
	content?: string | { "#text"?: string };
}

function parseDate(dateStr: string): string {
	try {
		const d = new Date(dateStr);
		return isNaN(d.getTime()) ? dateStr : d.toISOString();
	} catch {
		return dateStr;
	}
}

function isValidDate(dateStr: string): boolean {
	try {
		const d = new Date(dateStr);
		return !isNaN(d.getTime()) && d.getFullYear() >= 2020;
	} catch {
		return false;
	}
}

function isValidUrl(url: string): boolean {
	try {
		const u = new URL(url);
		if (u.protocol !== "http:" && u.protocol !== "https:") return false;
		if (u.hostname === "localhost" || u.hostname === "127.0.0.1") return false;
		return true;
	} catch {
		return false;
	}
}

function extractText(
	val: string | { "#text"?: string } | undefined,
): string | undefined {
	if (!val) return undefined;
	if (typeof val === "string") return val;
	return val["#text"];
}

function extractLink(item: ParsedItem): string | undefined {
	if (!item.link) return undefined;
	if (typeof item.link === "string") return item.link;
	return item.link["@_href"];
}

function parseFeedItems(xml: string, feedUrl: string): FeedPost[] {
	const doc = parser.parse(xml);

	// ---- RSS 2.0 ----
	const channel = doc?.rss?.channel;
	if (channel) {
		const items: ParsedItem[] = channel.item ?? [];
		if (!Array.isArray(items)) return [];
		return items.map((item: ParsedItem) => ({
			title: extractText(item.title) ?? "(untitled)",
			link: extractLink(item) ?? feedUrl,
			published: parseDate(item.pubDate ?? ""),
			description: extractText(item.description),
		}));
	}

	// ---- Atom ----
	const feed = doc?.feed;
	if (feed) {
		const entries: ParsedItem[] = feed.entry ?? [];
		if (!Array.isArray(entries)) return [];
		return entries.map((entry: ParsedItem) => ({
			title: extractText(entry.title) ?? "(untitled)",
			link: extractLink(entry) ?? feedUrl,
			published: parseDate(
				entry.published ?? entry.updated ?? "",
			),
			description: extractText(entry.summary ?? entry.content),
		}));
	}

	return [];
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
	const startTime = Date.now();

	// Read members
	const membersPath = path.join(__dirname, "../src/members.json");
	const members: Member[] = JSON.parse(
		await fs.readFile(membersPath, "utf-8"),
	);

	const cache: FeedCache = {};
	let totalFeeds = 0;
	let successCount = 0;
	let failCount = 0;

	// Read favicon manifest for later reference
	const manifestPath = path.join(
		__dirname,
		"../src/favicon-manifest.json",
	);
	let faviconManifest: Record<string, string> = {};
	try {
		faviconManifest = JSON.parse(
			await fs.readFile(manifestPath, "utf-8"),
		);
	} catch {
		// not critical
	}

	// Process members (skip index 0 = amrita.town itself)
	const membersToProcess = members.slice(1);

	console.log(
		`🔍 Discovering feeds for ${membersToProcess.length} members...`,
	);

	for (let i = 0; i < membersToProcess.length; i += CONCURRENCY_LIMIT) {
		const batch = membersToProcess.slice(i, i + CONCURRENCY_LIMIT);
		const results = await Promise.allSettled(
			batch.map(async (member) => {
				const { name, website, feeds: explicitFeeds } = member;

				// Determine feed URLs
				let feedUrls: string[];
				if (explicitFeeds && explicitFeeds.length > 0) {
					feedUrls = explicitFeeds;
				} else {
					console.log(`  🔎 ${website}: auto-discovering...`);
					feedUrls = await discoverFeeds(website);
				}

				if (feedUrls.length === 0) {
					console.log(`  ⚠️  ${website}: no feeds found`);
					return;
				}

				// Fetch all feeds for this member
				const allPosts: FeedPost[] = [];
				for (const feedUrl of feedUrls) {
					totalFeeds++;
					try {
						const res = await fetchWithTimeout(feedUrl);
						if (!res.ok) {
							console.log(
								`  ⚠️  ${website}: feed ${feedUrl} returned ${res.status}`,
							);
							failCount++;
							continue;
						}
						const xml = await res.text();
						const posts = parseFeedItems(xml, feedUrl);
						if (posts.length === 0) {
							console.log(
								`  ⚠️  ${website}: feed ${feedUrl} has no items`,
							);
						}
						allPosts.push(...posts);
						successCount++;
					} catch (err) {
						console.log(
							`  ⚠️  ${website}: failed to fetch ${feedUrl}: ${err instanceof Error ? err.message : err}`,
						);
						failCount++;
					}
				}

				if (allPosts.length === 0) return;

				// Sort by date descending, deduplicate by link
				const seen = new Set<string>();
				const unique = allPosts
					.sort(
						(a, b) =>
							new Date(b.published).getTime() -
							new Date(a.published).getTime(),
					)
					.filter((p) => {
						if (seen.has(p.link)) return false;
						if (!isValidDate(p.published)) return false;
						if (!isValidUrl(p.link)) return false;
						seen.add(p.link);
						return true;
					});

				if (unique.length === 0) return;

				cache[website] = {
					name,
					website,
					posts: unique,
				};

				console.log(
					`  ✅ ${website}: ${unique.length} posts from ${feedUrls.length} feed(s)`,
				);
			}),
		);

		for (const r of results) {
			if (r.status === "rejected") {
				console.error(`  ❌ batch error: ${r.reason}`);
			}
		}
	}

	// Write cache
	const cachePath = path.join(__dirname, "../src/feed-cache.json");
	await fs.writeFile(cachePath, JSON.stringify(cache, null, 2));
	console.log(`📝 Feed cache written to src/feed-cache.json`);

	// Summary
	const duration = ((Date.now() - startTime) / 1000).toFixed(1);
	const memberCount = Object.keys(cache).length;
	const postCount = Object.values(cache).reduce(
		(sum, m) => sum + m.posts.length,
		0,
	);
	console.log(
		`📊 Summary: ${memberCount}/${membersToProcess.length} members with feeds, ${postCount} posts total, ${totalFeeds} feeds fetched in ${duration}s`,
	);
	if (failCount > 0) {
		console.log(`   ${failCount} feed(s) failed to fetch`);
	}
}

main().catch((err) => {
	console.error("❌ Fatal error:", err);
	process.exit(1);
});
