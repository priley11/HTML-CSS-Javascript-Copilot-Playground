# CLAUDE.md

Static HTML/CSS/JS playground: `index.html`, `style.css`, `script.js`.

## Stock photos (Pexels, Unsplash)

Use `tools/photos.sh` to find images instead of guessing image URLs:

    tools/photos.sh <pexels|unsplash|all> "<query>" [count]

It prints one JSON object per photo (`image_url`, `alt`, `photographer`, `page_url`, ...).
It needs `PEXELS_API_KEY` and/or `UNSPLASH_ACCESS_KEY` in the environment, plus `curl` and `jq`.

Rules when using results in the page:
- Never put an API key in `index.html`, `script.js`, or any committed file. This site is static, so a key in the page is public.
- Hotlink `image_url` directly (Unsplash requires this; do not re-host).
- Credit the photographer next to the image, linking `photographer_url` and the source site
  (e.g. "Photo by <a href=...>Name</a> on <a href="https://unsplash.com">Unsplash</a>").
- Use `alt` as the image's alt text, rewritten if it's empty or unhelpful.
