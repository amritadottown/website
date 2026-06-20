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

export interface MemberFeedCache {
	name: string;
	website: string;
	favicon: string;
	posts: FeedPost[];
	feedUrls?: string[];
}

export type FeedCache = Record<string, MemberFeedCache>;
