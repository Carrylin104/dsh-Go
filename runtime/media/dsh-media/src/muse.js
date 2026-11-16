// Muse is a user-hosted gateway. Only its explicitly configured origin may use
// HTTP/private addresses; result links elsewhere keep the public HTTPS policy.
import { parseMediaUrl } from './http.js';
import { fail } from './errors.js';

export const isMuseProfile = profile => ['muse-image', 'muse-video'].includes(profile);

export function museApiRoot(value) {
  let url;
  try { url = new URL(value); } catch { fail('unsafe_url'); }
  if (!['http:', 'https:'].includes(url.protocol) || !url.hostname
    || url.username || url.password || url.search || url.hash
    || typeof value !== 'string' || value.length > 2048 || /[\s\\\x00-\x1f\x7f]/.test(value)) fail('unsafe_url');
  const path = url.pathname.replace(/\/+$/, '');
  if (/\/(admin|images|videos|chat|responses)(\/|$)/i.test(path)) fail('unsafe_url');
  return url.origin + path + (path.endsWith('/v1') ? '' : '/v1');
}

export function museMediaUrl(value, service) {
  if (typeof value !== 'string' || !value) fail('response');
  let url;
  try { url = new URL(value, museApiRoot(service.baseUrl) + '/').href; }
  catch { fail('unsafe_url'); }
  parseMediaUrl(url, { trustedOrigin: new URL(service.baseUrl).origin });
  return url;
}

export function mediaDownloadOptions(url, service, secret) {
  if (!isMuseProfile(service.profile)) return {};
  const origin = new URL(museApiRoot(service.baseUrl)).origin;
  const parsed = parseMediaUrl(url, { trustedOrigin: origin });
  return parsed.origin === origin
    ? { trustedOrigin: origin, headers: { authorization: 'Bearer ' + secret } }
    : {};
}
