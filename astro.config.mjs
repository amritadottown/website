import { defineConfig } from 'astro/config';
import cloudflare from '@astrojs/cloudflare';

import mdx from '@astrojs/mdx';

// https://astro.build/config
export default defineConfig({
	site: 'https://amrita.town',
	output: 'static',
	adapter: cloudflare(),
	integrations: [mdx()],
	markdown: {
		shikiConfig: {
			themes: {
				light: 'material-theme-lighter',
				dark: 'material-theme-darker',
			},
		},
	},
});
