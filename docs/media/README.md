# Media

Recorded with `scripts/demo/record.sh` (`BACKDROP=wallpaper WALLPAPER=frame.png` for the wallpaper versions) from a scripted demo with made-up sessions (no real data), on a
plain stage. Regenerate after UI changes (about 90 seconds for all three; leave the mouse alone).

| File | Use | Size |
|---|---|---|
| `triage-demo[-wallpaper].mp4` / `.webm` / `.gif` | Hero: a request opens, one click approves it, the card lists sessions and terminals (12.9s) | 1440x940 (GIF 720x470) |
| `triage-pill[-wallpaper].mp4` / `.webm` / `.gif` | Features: the pill alone, including the red "1 pending" alert (9.8s) | 1440x220 (GIF 720x110) |
| `triage-music[-wallpaper].mp4` / `.webm` / `.gif` | Features: the pill slides aside when a Live Activity opens in the island (7.8s) | 1440x220 (GIF 720x110) |
| `*-poster.png` | Video placeholder frames | 1440 wide |
| `social.png` | Social/link preview image | 1200x630 |

**The `*-wallpaper.*` files are the primary set** (the README uses them): the same story on a real desktop
wallpaper (a still frame from the macOS "Aerial" blue-streak wallpaper). The files without the suffix are the
same clips on a plain dark stage, for pages where a quieter backdrop suits better. The wallpaper is Apple's
artwork.

The Live Activity in `triage-music` is a stand-in drawn by the demo (no real music or album art).

For a site, use the MP4 with the WebM as a fallback, and a poster:

```html
<video autoplay loop muted playsinline poster="triage-demo-wallpaper-poster.png">
  <source src="triage-demo-wallpaper.webm" type="video/webm">
  <source src="triage-demo-wallpaper.mp4" type="video/mp4">
</video>
```

The GIFs are for places that can't play video (the README). Set the social image with
`<meta property="og:image" content="https://…/social.png">` and `twitter:card` `summary_large_image`.
