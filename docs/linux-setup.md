# Linux Setup Instructions
`<project root>` below refers to wherever this git repository was cloned to.

## Configure
1. Install [stack](https://docs.haskellstack.org/en/stable/README/#how-to-install)
1. Install the SDL2, SDL2\_image, SDL2\_ttf libraries from your distribution's package manager e.g.:
   - Ubuntu: `sudo apt install libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev`
   - Arch Linux: `sudo pacman -S sdl2 sdl2_image sdl2_ttf`

#### Enable Game Audio (optional)
1. Register for a [FMOD account](https://www.fmod.com/profile/register)
1. Download and extract ["FMOD Engine 2.02.08"](https://fmod.com/download#fmodengine) (Linux)
1. From the extracted contents:
   - Copy `api/core/inc/*.h` into `<project root>/inc/`
   - Copy `api/studio/inc/*.h` into `<project root>/inc/`
   - Copy `api/core/lib/x86_x64/libfmod.so*` into `<project root>/lib/`
   - Copy `api/studio/lib/x86_x64/libfmodstudio.so*` into `<project root>/lib/`
1. Edit the lines at the bottom of `<project root>/package.yaml`:
   - In the `c-sources:` line change `wrapper-NOAUDIO.c` to `wrapper.c`
   - Uncomment the `extra-lib-dirs` and `extra-libraries` lines
1. After building run the game with: `LD_LIBRARY_PATH=<project root>/lib ./defect-process`

## Build
`stack build --local-bin-path . --copy-bins` (ignore any warnings about PATH)

## Run
This assumes you've purchased a copy of the [game on Steam](https://store.steampowered.com/app/1136730/Defect_Process/).

1. From the Steam client right click the Defect Process entry in the games library `-> Properties -> Betas`
   - Change the selected beta from "None" to "github - branch for github"
1. From the Steam client right click the Defect Process entry in your games library `-> Properties -> Local Files -> Browse`. The file explorer window that pops up should be in the installed steam game directory:
   - Copy the contents of `<steam game directory>/data/` into `<project root>/data/`
1. From `<project root>` run `./defect-process`

See [docs/dev-console-reference.pdf](https://github.com/incoherentsoftware/defect-process/blob/main/docs/dev-console-reference.pdf) for what dev console commands are available.
