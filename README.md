# Retro games in the browser

Classic open-source game engines compiled to WebAssembly with Emscripten. One folder per game;
each has its own `build.sh`, `README.md` and `dist/` (the playable static site).

| Game | Folder | Engine | Game data |
|---|---|---|---|
| Prince of Persia (1989) | [`prince-of-persia/`](prince-of-persia/) | SDLPoP | ships with SDLPoP |
| Endless Sky (v0.11.2) | [`endless-sky/`](endless-sky/) | Endless Sky, web changes based on [endless-web](https://github.com/thomasballinger/endless-web) | ships with the game (GPLv3 code, CC / public-domain art) |
| Cave Story (2004) | `cave-story/` | in progress | freeware |
| Quake (1996) | `quake/` | in progress | shareware episode |

## Play online

- Prince of Persia: <https://ankit1324.github.io/game-to-browser/prince-of-persia/dist/>
- Endless Sky: <https://ankit1324.github.io/game-to-browser/endless-sky/dist/> (the first visit downloads 395 MB)

## Play locally

```sh
python3 -m http.server 8080 -d . --bind 127.0.0.1
```

Then open `http://127.0.0.1:8080/<folder>/dist/`.
