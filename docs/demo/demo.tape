# Generates docs/demo.gif — run from the repository root:  vhs docs/demo/demo.tape
# Requires VHS (brew install vhs). Everything runs in a throw-away sandbox (docs/demo/setup.sh).
Output docs/demo.gif

Set Shell "bash"
Set FontSize 20
Set Width 1200
Set Height 640
Set Padding 24
Set TypingSpeed 45ms
Set WindowBar Colorful

Hide
Type "source docs/demo/setup.sh && clear"
Enter
Sleep 2s
Show

Type "ccprof list"
Sleep 400ms
Enter
Sleep 3.5s

Type "cd ~/work/client-app && claude"
Sleep 400ms
Enter
Sleep 2.5s

Type "cd ~/work/platform && claude"
Sleep 400ms
Enter
Sleep 2.5s

Type "cd ~/personal/blog && claude"
Sleep 400ms
Enter
Sleep 2.5s

Type "clear"
Enter
Type "cd ~/Downloads/some-repo && claude"
Sleep 400ms
Enter
Sleep 3s

Type "ccprof bind personal && claude"
Sleep 400ms
Enter
Sleep 4s

# Back to the repository (hidden), so the GIF is written to docs/demo.gif
Hide
Type 'cd "$CCPROF_DEMO_SRC" && clear'
Enter
Sleep 500ms
