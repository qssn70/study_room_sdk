export function trustProxyHops(value = process.env.STUDY_ROOM_TRUST_PROXY_HOPS): number {
  if (value === undefined || value === '') return 0;
  if (!/^\d+$/.test(value)) {
    throw new Error('STUDY_ROOM_TRUST_PROXY_HOPS must be a non-negative safe integer');
  }
  const hops = Number(value);
  if (!Number.isSafeInteger(hops)) {
    throw new Error('STUDY_ROOM_TRUST_PROXY_HOPS must be a non-negative safe integer');
  }
  return hops;
}
