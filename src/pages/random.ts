import type { APIRoute } from 'astro';
import members from '@/members.json';

export const prerender = false;

export const GET: APIRoute = ({ request, url, redirect }) => {
	const index = Math.floor(Math.random() * members.length);
	return redirect(members[index].website, 302);
};
