import type { APIRoute } from 'astro';
import members from '@/members.json';

export const prerender = false;

export const GET: APIRoute = ({ request, url, redirect }) => {
	if(!url.searchParams.get('site') && !request.headers.get('Referer'))
	{
		const index = Math.floor(Math.random() * members.length);
		return redirect(`https://${members[index].website}/`, 302);
	}

	const key = url.searchParams.get('site') ?? new URL(request.headers.get('Referer')).host;
	const currentIndex = members.findIndex((e) => e.website === key);
	let index = -1;
	do {
		index = Math.floor(Math.random() * members.length);
	} while(index === currentIndex); // this probably breaks horribly with only 1 member. we're cooler than that tho

	return redirect(`https://${members[index].website}/`, 302);
};
