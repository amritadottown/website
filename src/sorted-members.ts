import members from '@/members.json';

export type Member = (typeof members)[number];

const gradYearOf = (batch: string) => {
	const end = batch.split('-')[1];
	return end ? parseInt(end, 10) : -1;
};

// members sorted youngest first (descending graduation year).
// entries without a batch (e.g. the ring's own site) sort last.
export const sortedMembers: Member[] = [...members].sort(
	(a, b) => gradYearOf(b.batch) - gradYearOf(a.batch),
);

export default sortedMembers;
