import { act, cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'

import { I18nProvider } from '@/i18n/context'
import { $updateOverlayOpen, $updateOverlayTarget, $updateStatus } from '@/store/updates'

import { UpdatesOverlay } from './updates-overlay'

// This fork disables updates, and the overlay's `supported: false` branch is
// the ONLY screen a user reaches for it — there is no install button, so
// nothing dispatches `updates:apply`. An earlier attempt put the explanation
// in a window opened from that handler, which therefore never opened. These
// tests pin the reachable path instead of the piece behind it.
async function renderOverlay() {
  let container: HTMLElement | undefined

  await act(async () => {
    container = render(
      <I18nProvider configClient={{ getConfig: async () => ({}), saveConfig: async () => ({ ok: true }) }}>
        <UpdatesOverlay />
      </I18nProvider>
    ).baseElement as HTMLElement
  })

  return container as HTMLElement
}

describe('UpdatesOverlay — updates disabled', () => {
  afterEach(() => {
    cleanup()
    $updateOverlayOpen.set(false)
    $updateOverlayTarget.set('client')
    $updateStatus.set(null)
  })

  it('shows the reason and the image on the screen the user actually lands on', async () => {
    $updateOverlayTarget.set('client')
    $updateOverlayOpen.set(true)
    $updateStatus.set({ message: 'Обновление недоступно.', supported: false } as never)

    const container = await renderOverlay()

    expect(screen.getByText(/Обновление недоступно/)).toBeTruthy()

    const image = container.querySelector('img[src$="update-disabled.gif"]')

    expect(image).not.toBeNull()
  })

  it('offers no way to start an update', async () => {
    $updateOverlayTarget.set('client')
    $updateOverlayOpen.set(true)
    $updateStatus.set({ message: 'Обновление недоступно.', supported: false } as never)

    await renderOverlay()

    for (const button of screen.queryAllByRole('button')) {
      expect(button.textContent ?? '').not.toMatch(/install|update|обнов/i)
    }
  })
})
