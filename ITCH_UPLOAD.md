# Publishing Night Run on itch.io

**Ready to upload:** `build/night-run-web.zip` — 23 MB, `index.html` at the
root, which is what itch requires.

Verified before packaging: I served the exact zip contents from a random
subdirectory inside a sandboxed iframe — the way itch actually serves games —
loaded the menu, hit Play, and moved the character. It works in that context,
not just from a plain local server.

I can't do the upload itself. It needs an account, and I don't log into
accounts on your behalf. The steps below are the whole job — about two minutes.

## Steps

1. Sign in at **itch.io**, then **Dashboard → Create new project**.
2. Fill in:
   - **Title:** Night Run
   - **Classification:** Game
   - **Kind of project: HTML** ← the important one; the default is Downloadable
3. **Upload** `build/night-run-web.zip`, then tick the box that appears on it:
   **"This file will be played in the browser"**
4. Embed options:
   - **Viewport:** `960` × `540`
   - ✅ Fullscreen button
   - ⬜ **SharedArrayBuffer support — leave this OFF.** The build was exported
     without thread support precisely so it needs no COOP/COEP headers.
     Turning it on adds them and can break loading for no benefit here.
   - ⬜ Mobile friendly — see the note below before deciding
5. **Visibility:** Draft while you check it, then Public when you're happy.
   A draft still gives you a shareable link.
6. **Save**, then **View page** and play it through once.

## Two things worth knowing

**The security headers don't apply on itch.** `build/web/_headers` is a
Netlify/Cloudflare file; itch ignores it, so the Content-Security-Policy and
the Permissions-Policy I wrote are inert there.

That is less bad than it sounds — itch serves game content from a **separate
domain** (`itch.zone`, not `itch.io`) inside a **sandboxed iframe**, which is
real isolation and is why it's a reasonable place to put a link you're sending
to people. But it is itch's isolation doing the work, not mine. If you want the
headers I wrote to actually apply, deploy `build/web/` to **Cloudflare Pages or
Netlify** instead; both read `_headers` automatically and it's the same drag-
and-drop effort.

**Mobile.** The touch controls only appear on a touch device, so the itch
"mobile friendly" flag is worth ticking if you want phone players. I have
tested the pad layout in a 19.5:9 render and in a desktop browser, but **not on
a real phone** — try it on your own before advertising it as mobile-ready.

## If you turn telemetry on later

itch serves from `itch.zone`, so the origin the browser sends is not
`itch.io`. Set `ALLOWED_ORIGINS` on the backend to whatever the browser
actually reports — open the game, check the network tab's `Origin` header, and
use exactly that. Guessing will just produce 403s.

Telemetry is off by default, so none of this blocks publishing today.
