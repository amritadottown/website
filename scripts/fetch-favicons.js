import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONCURRENCY_LIMIT = 5;
const TIMEOUT_MS = 8000;

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
	 */
	getRootDomain(website) {
		return website.split('/')[0];
	}

	/**
	 * Sanitize website string for use as filename
	 * e.g., "ngpal.github.io/brainspace" -> "ngpal.github.io-brainspace"
	 */
	sanitizeFilename(website) {
		return website.replace(/\//g, '-');
	}

	/**
	 * Try fetching favicon with a simple, fast strategy:
	 * 1. Google's favicon service (fast, reliable)
	 * 2. Direct favicon.ico from site (fallback)
	 */
	async tryFetchFavicon(website) {
		const rootDomain = this.getRootDomain(website);

		// Primary: Google's favicon service (most reliable and fast)
		try {
			const googleUrl = `https://www.google.com/s2/favicons?domain=${rootDomain}&sz=32`;
			const response = await this.fetchWithTimeout(googleUrl);
			if (response.ok) {
				const data = await response.arrayBuffer();
				// Google returns a default globe icon for unknown domains (small size)
				// Accept if it's reasonably sized (> 100 bytes)
				if (data.byteLength > 100) {
					return data;
				}
			}
		} catch {
			// Fall through to other fallbacks
		}

		// Secondary: DuckDuckGo's icons service (another reliable, lightweight source)
		try {
			const ddgUrl = `https://icons.duckduckgo.com/ip3/${rootDomain}.ico`;
			const response = await this.fetchWithTimeout(ddgUrl);
			if (response.ok) {
				const data = await response.arrayBuffer();
				// Accept if non-trivial (avoids empty/placeholder responses)
				if (data.byteLength > 100) {
					return data;
				}
			}
		} catch {
			// Fall through to direct site fetch
		}

		// Fallback: Try direct favicon files from site
		const faviconPaths = ['/favicon.svg', '/favicon.ico', '/favicon.png'];
		for (const targetPath of [website, rootDomain]) {
			for (const faviconFile of faviconPaths) {
				try {
					const url = `https://${targetPath}${faviconFile}`;
					const response = await this.fetchWithTimeout(url);
					if (response.ok) {
						const contentType = response.headers.get('content-type');
						if (contentType?.startsWith('image/')) {
							return await response.arrayBuffer();
						}
					}
				} catch {
					// Silent fail, try next
				}
			}
		}

		return null;
	}

	/**
	 * Fetch favicon for a single member
	 */
	async fetchFaviconForMember(member, index, total) {
		const { website } = member;

		try {
			const faviconData = await this.tryFetchFavicon(website);

			if (faviconData) {
				// Save favicon to public/favicons/
				const sanitized = this.sanitizeFilename(website);
				const filename = `${sanitized}.ico`;
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
				// Mark as needing fallback in manifest
				this.manifest[website] = null;
				this.failCount++;
				console.log(
					`⚠️  ${website}: using fallback (${index + 1}/${total})`,
				);
			}
		} catch (error) {
			this.manifest[website] = null;
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
			`\n📊 Summary: ${fetcher.successCount} fetched, ${fetcher.failCount} fallback (${duration}s)`,
		);
	} catch (error) {
		console.error('❌ Fatal error:', error.message);
		process.exit(1);
	}
}

main();
