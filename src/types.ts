export interface Member {
	name: string;
	website: string;
	branch: string;
	campus: string;
	batch: string;
	feeds?: string[];
}

export interface FeedPost {
	title: string;
	link: string;
	published: string;
	description?: string;
}

/**
 * Feed cache: posts only, keyed by member website.
 * Members.json is the source of truth for identity + feed URLs;
 * this cache holds just the volatile post content fetched at build time.
 */
export type FeedCache = Record<string, FeedPost[]>;
