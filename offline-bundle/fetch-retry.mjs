// Preloaded by build-bundle.bat into the desktop packaging step
// (NODE_OPTIONS=--import ...). Not part of the bundle and not used at runtime.
//
// electron-builder fetches Electron, its SHASUMS256.txt and the Windows
// packaging tools from GitHub with Node's global fetch. Its undici agent gives
// up on a TCP connect after 10 s, and electron-builder's own retry does not
// recognise that error (the code sits in error.cause), so one dropped
// connection to github.com fails the whole build with "TypeError: fetch failed".
// Worse, a failed SHASUMS256.txt check throws away the 110 MB Electron zip that
// was just downloaded. This wrapper retries a request that never got a response
// because the connection could not be made or was cut.

const RETRYABLE = new Set([
  'UND_ERR_CONNECT_TIMEOUT',
  'UND_ERR_SOCKET',
  'UND_ERR_HEADERS_TIMEOUT',
  'ECONNRESET',
  'ECONNREFUSED',
  'ETIMEDOUT',
  'EAI_AGAIN',
  'ENOTFOUND',
  'EPIPE',
])
const ATTEMPTS = 6

/** @param {unknown} error @returns {string | undefined} */
function causeCode(error) {
  let current = /** @type {any} */ (error)
  while (current) {
    if (typeof current.code === 'string' && RETRYABLE.has(current.code)) return current.code
    current = current.cause
  }
  return undefined
}

const original = globalThis.fetch
if (typeof original === 'function' && !original.__hermesRetry) {
  /** @type {typeof fetch} */
  const withRetry = async (input, init) => {
    for (let attempt = 1; ; attempt++) {
      try {
        return await original(input, init)
      } catch (error) {
        const code = causeCode(error)
        if (!code || attempt >= ATTEMPTS || init?.signal?.aborted) throw error
        const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
        const delay = 2000 * attempt
        process.stderr.write(`  [fetch-retry] ${code} on ${url} - attempt ${attempt + 1} of ${ATTEMPTS} in ${delay / 1000} s\n`)
        await new Promise(resolve => setTimeout(resolve, delay))
      }
    }
  }
  withRetry.__hermesRetry = true
  globalThis.fetch = withRetry
}
