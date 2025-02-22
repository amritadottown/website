import type { APIRoute } from 'astro';
import members from '@/members.json';

export const prerender = false;

export const GET: APIRoute = ({ url, request, redirect }) => {
	if(!url.searchParams.get('site') && !request.headers.get('Referer'))
		return redirect(`https://amrita.town`, 302);
	
	let key = url.searchParams.get('site') ?? new URL(request.headers.get('Referer')).host;

	if (key) {
		const index = members.findIndex((e) => e.website === key);
		if (index !== -1) {
			const prev = index === 0 ? members.length - 1 : index - 1;
			return redirect(`https://${members[prev].website}/`, 302);
		}
	}

	return redirect('/', 302);
};
