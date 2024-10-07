import { defineConfig } from 'astro/config';
import cloudflare from '@astrojs/cloudflare';

import mdx from '@astrojs/mdx';

// https://astro.build/config
export default defineConfig({
	site: 'https://amrita.town',
	output: 'hybrid',
	adapter: cloudflare(),
	integrations: [mdx()],
});
