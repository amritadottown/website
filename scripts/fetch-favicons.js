import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONCURRENCY_LIMIT = 5;
const TIMEOUT_MS = 10000;

class FaviconFetcher {
	constructor() {
		this.successCount = 0;
		this.failCount = 0;
		this.manifest = {};
	}

	/**
	 * Fetch with timeout support
	 */
	async fetchWithTimeout(url, timeout = TIMEOUT_MS) {
		const controller = new AbortController();
		const timeoutId = setTimeout(() => controller.abort(), timeout);

		try {
			const response = await fetch(url, {
				signal: controller.signal,
				headers: {
					'User-Agent': 'amrita.town-webring/1.0',
				},
			});
			clearTimeout(timeoutId);
			return response;
		} catch (error) {
			clearTimeout(timeoutId);
			throw error;
		}
	}

	/**
	 * Extract root domain from website string
	 * e.g., "ngpal.github.io/brainspace" -> "ngpal.github.io"
	 * e.g., "https://example.com/path?q=1" -> "example.com"
	 */
	getRootDomain(website) {
		try {
			const urlStr = website.startsWith('http') ? website : `https://${website}`;
			return new URL(urlStr).hostname;
		} catch (error) {
			// Fallback if URL constructor fails
			return website.replace(/^https?:\/\//, '').split('/')[0].split('?')[0];
		}
	}

	/**
	 * Sanitize website string for use as filename
	 * e.g., "ngpal.github.io/brainspace" -> "ngpal.github.io-brainspace"
	 */
	sanitizeFilename(website) {
		return website
			.replace(/^https?:\/\//, '') // Remove protocol
			.split('?')[0]               // Remove query parameters
			.split('#')[0]               // Remove hash fragments
			.replace(/\/+$/, '')         // Remove trailing slashes
			.replace(/[^a-zA-Z0-9.-]/g, '-'); // Replace invalid file characters with dash
	}

	getExtension(contentType, url = '') {
		if (!contentType) {
			if (url.endsWith('.svg')) return '.svg';
			if (url.endsWith('.ico')) return '.ico';
			if (url.endsWith('.png')) return '.png';
			return '.png';
		}
		if (contentType.includes('svg')) return '.svg';
		if (contentType.includes('png')) return '.png';
		if (contentType.includes('gif')) return '.gif';
		if (contentType.includes('jpeg') || contentType.includes('jpg')) return '.jpg';
		if (contentType.includes('x-icon') || contentType.includes('vnd.microsoft.icon')) return '.ico';
		
		if (url.endsWith('.svg')) return '.svg';
		if (url.endsWith('.ico')) return '.ico';
		if (url.endsWith('.png')) return '.png';
		
		return '.png';
	}

	/**
	 * Try fetching favicon from multiple sources with fallback strategy
	 */
	async tryFetchFavicon(website) {
		const rootDomain = this.getRootDomain(website);
		const protocols = ['https', 'http'];

		// Try parsing HTML for favicon link
		for (const protocol of protocols) {
			try {
				const url = `${protocol}://${website}`;
				const response = await this.fetchWithTimeout(url);
				if (response.ok) {
					const contentType = response.headers.get('content-type');
					if (contentType && contentType.includes('text/html')) {
						const html = await response.text();
						// Match <link rel=icon href=...> in any order, with
					// quoted ("..." or '...') OR unquoted attribute values
					// (valid HTML5 — e.g. <link rel=icon href=/foo.svg>).
					const linkRegex = /<link[^>]*?rel\s*=\s*["']?(?:shortcut\s+)?icon["']?[^>]*?href\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>|<link[^>]*?href\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*?rel\s*=\s*["']?(?:shortcut\s+)?icon["']?[^>]*>/i;
						const match = html.match(linkRegex);
						const iconHref = match
							? (match[1] || match[2] || match[3] || match[4] || match[5] || match[6])
							: null;

						if (iconHref) {
							let iconUrl = iconHref;
							if (!iconUrl.startsWith('http')) {
								if (iconUrl.startsWith('//')) {
									iconUrl = `${protocol}:${iconUrl}`;
								} else if (iconUrl.startsWith('/')) {
									iconUrl = `${protocol}://${rootDomain}${iconUrl}`;
								} else {
									iconUrl = `${protocol}://${website}/${iconUrl}`;
								}
							}
							const iconResponse = await this.fetchWithTimeout(iconUrl);
							if (iconResponse.ok) {
								const iconContentType = iconResponse.headers.get('content-type');
								if (iconContentType && iconContentType.startsWith('image/')) {
									const ext = this.getExtension(iconContentType, iconUrl);
									return { data: await iconResponse.arrayBuffer(), ext };
								}
							}
						}
					}
				}
			} catch (error) {
				// Silent fail
			}
		}

		const paths = [website, rootDomain];
		const filenames = ['favicon.ico', 'favicon.png', 'favicon.svg'];

		// Try combinations of protocol, path, and filename
		for (const protocol of protocols) {
			for (const targetPath of paths) {
				// Skip duplicate if website has no subdirectory
				if (
					targetPath === rootDomain &&
					website === rootDomain &&
					protocol === 'http'
				) {
					continue;
				}

				for (const filename of filenames) {
					const url = `${protocol}://${targetPath}/${filename}`;
					try {
						const response = await this.fetchWithTimeout(url);
						if (response.ok) {
							const contentType =
								response.headers.get('content-type');
							// Verify it's actually an image
							if (
								contentType &&
								contentType.startsWith('image/')
							) {
								const ext = this.getExtension(contentType, url);
								return { data: await response.arrayBuffer(), ext };
							}
						}
					} catch (error) {
						// Silent fail, try next option
					}
				}
			}
		}

		// Final fallback: Google's favicon service
		try {
			const googleUrl = `https://www.google.com/s2/favicons?domain=${rootDomain}&sz=32`;
			const response = await this.fetchWithTimeout(googleUrl);
			if (response.ok) {
				const contentType = response.headers.get('content-type');
				const ext = this.getExtension(contentType, googleUrl);
				return { data: await response.arrayBuffer(), ext };
			}
		} catch (error) {
			// All options exhausted
		}

		return null;
	}

	/**
	 * Fetch favicon for a single member
	 */
	async fetchFaviconForMember(member, index, total) {
		const { website, name } = member;

		try {
			const result = await this.tryFetchFavicon(website);

			if (result && result.data) {
				const { data: faviconData, ext } = result;
				// Save favicon to public/favicons/
				const sanitized = this.sanitizeFilename(website);
				const filename = `${sanitized}${ext}`;
				const faviconPath = path.join(
					__dirname,
					'../public/favicons',
					filename,
				);

				await fs.writeFile(faviconPath, Buffer.from(faviconData));

				// Add to manifest
				this.manifest[website] = `/favicons/${filename}`;
				this.successCount++;
				console.log(`✅ ${website} (${index + 1}/${total})`);
			} else {
				this.failCount++;
				console.log(
					`⚠️  ${website}: All sources failed, using fallback (${index + 1}/${total})`,
				);
			}
		} catch (error) {
			this.failCount++;
			console.log(
				`⚠️  ${website}: ${error.message} (${index + 1}/${total})`,
			);
		}
	}

	/**
	 * Process members in batches with concurrency control
	 */
	async fetchAllFavicons(members) {
		const total = members.length;
		console.log(
			`🔍 Fetching favicons for ${total} members (${CONCURRENCY_LIMIT} concurrent)...`,
		);

		// Process in batches
		for (let i = 0; i < members.length; i += CONCURRENCY_LIMIT) {
			const batch = members.slice(i, i + CONCURRENCY_LIMIT);
			const promises = batch.map((member, batchIndex) =>
				this.fetchFaviconForMember(member, i + batchIndex, total),
			);
			await Promise.allSettled(promises);
		}
	}

	/**
	 * Write manifest to src/favicon-manifest.json
	 */
	async writeManifest() {
		const manifestPath = path.join(
			__dirname,
			'../src/favicon-manifest.json',
		);
		await fs.writeFile(
			manifestPath,
			JSON.stringify(this.manifest, null, 2),
		);
		console.log(`📝 Manifest written to src/favicon-manifest.json`);
	}
}

async function main() {
	const startTime = Date.now();

	try {
		// Read members.json
		const membersPath = path.join(__dirname, '../src/members.json');
		const membersData = await fs.readFile(membersPath, 'utf-8');
		const members = JSON.parse(membersData);

		// Create public/favicons directory if it doesn't exist
		const faviconsDir = path.join(__dirname, '../public/favicons');
		await fs.mkdir(faviconsDir, { recursive: true });

		// Fetch all favicons
		const fetcher = new FaviconFetcher();
		await fetcher.fetchAllFavicons(members);

		// Write manifest
		await fetcher.writeManifest();

		// Summary
		const duration = ((Date.now() - startTime) / 1000).toFixed(1);
		console.log(
			`📊 Summary: Successfully fetched ${fetcher.successCount}/${members.length} favicons in ${duration}s`,
		);

		if (fetcher.failCount > 0) {
			console.log(
				`   ${fetcher.failCount} favicon(s) will use the amrita.town fallback logo`,
			);
		}
	} catch (error) {
		console.error('❌ Fatal error:', error.message);
		process.exit(1);
	}
}

main();
