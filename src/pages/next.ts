import type { APIRoute } from 'astro';
import members from '@/members.json';

export const prerender = false;

export const GET: APIRoute = ({ url, request, redirect }) => {
	let key = url.searchParams.get('site') ?? request.headers.get('Referer');

	if (key) {
		const index = members.findIndex((e) => e.website === key);
		if (index !== -1) {
			const prev = index === members.length - 1 ? 0 : index + 1;
			return redirect(`https://${members[prev].website}/`, 302);
		}
	}
	
	return redirect('/', 302);
};
