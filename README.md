# rex-sessionizer

Pick a project with `fzf`, create a Rex session in that directory, and switch to
it. Selecting the project again reuses its session and preserves its tabs.

> **Enable automatic switching:** In Rex, open **Settings → Rex Server** and
> turn on **Remote Control**. This is a one-time setup. Run `./rex-sessionizer`
> and choose a project; Rex will automatically navigate to its session.
> If Remote Control is disabled, the session is created but switching reports
> an error. Use `--no-switch` to create or reuse sessions without navigation.

The only source is `~/Dev/personal/experiments`. Only immediate, visible
directories appear; hidden directories, files, nested projects, and directory
symlinks are excluded.

Uses Bash 3.2+ (including macOS's built-in Bash), `fzf`, `jq`, and Rex. SHA-256
uses macOS's `shasum`, or `sha256sum` on Linux. No package build or runtime to
install. Rex must be installed separately; this script uses its documented CLI.

```sh
brew install fzf jq
./rex-sessionizer                 # fuzzy picker
./rex-sessionizer reki            # choose by project name
./rex-sessionizer "$HOME/Dev/personal/experiments/reki"
./rex-sessionizer --list          # show available projects
./rex-sessionizer --no-switch reki # create/reuse without displaying
```

For convenient access, run this once from this repository:

```sh
mkdir -p "$HOME/.local/bin"
ln -s "$PWD/rex-sessionizer" "$HOME/.local/bin/rex-sessionizer"
```

Ensure `~/.local/bin` is on your shell's `PATH`. In Fish, for example:

```fish
fish_add_path ~/.local/bin
alias --save rxs rex-sessionizer
```

`--save` persists the alias so it is available in future Fish sessions. After
linking the executable and saving the alias, run `rxs` from any directory.

The script looks for `rex` on `PATH`, then inside `/Applications/Rex.app` and
`/Applications/Rex Beta.app`. Set `REX_BIN` to override its executable.

With multiple connected apps, set `REX_CLIENT` to the intended client ID from
`rex client ls --json`. Disconnected apps are ignored. `--no-switch` works
without an app or Remote Control. Successful opens print the session ID.
Canceling the picker makes no Rex calls and exits successfully.

Session labels look like `reki [a1b2c3d4e5f6]`: the project name plus the first
12 hex characters of SHA-256 of its canonical absolute path. There is no state
file. Keep this generated label to preserve automatic reuse. Moving a project,
renaming its session, or closing the session means a new session is created on
the next visit. Launch the picker once at a time; simultaneous first opens can
create duplicate sessions, which the script reports on subsequent visits.

## Tests

```sh
bash tests/test.sh
```

The regression suite uses temporary directories, a fake Rex CLI, and the real
`fzf` in filter mode. It creates and removes its own fixture directories inside
the source, and never contacts your Rex server.

To run it in a Rex terminal and retain the results:

```sh
rex new rex-sessionizer-tests -c "$PWD" --window Regression \
  --keep-open --shell=none --json -- /bin/bash tests/test.sh
```

Use `rex capture -s SESSION_ID -b BLOCK_ID --trim` with the returned IDs to
read the results. For a live smoke test, open `./rex-sessionizer` in a Rex
terminal, select a project, and select it again to confirm reuse. Escape should
exit without creating a session. Live switching requires Remote Control;
`--no-switch` still creates or reuses sessions with that setting disabled.
