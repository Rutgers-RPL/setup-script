# Setting up RPL dev environment
## Step 1:
[This](https://learn.microsoft.com/en-us/windows/wsl/install) page from windows covers everything you need to do to install wsl. If you care to select which distro, you can read how to do it there. If you don't care, just open cmd as admin and run
```
wsl --install
```
and then restart your computer. Now that you have wsl installed, open up cmd again, and type wsl. This will open your default distro. After that, it will prompt you to make a username and password. Make sure you remember this password.

## Step 2: Installing tools
Run
```
curl -fsSL https://raw.githubusercontent.com/Rutgers-RPL/setup-script/refs/heads/main/setup.sh | bash
```
This will install CMake, Ninja, gcc-arm-none-eabi, and a few other tools you will need. 

## Step 3 (optional): Setting up VS Code
Make sure you have vscode installed, and add it to your path. In wsl, you should just be able to type `code .` in any folder to open that folder in vscode. The only extension that really helps is clangd. For clangd to work, put something like this 
```
{
    "clangd.path": "/usr/bin/clangd",
    "clangd.arguments": [
        "--compile-commands-dir=build/Debug",
        "--query-driver=/usr/bin/arm-none-eabi-gcc",
        "--background-index"
    ]
}
```
In your `.vscode/setting.json` file. Note that --compile-commands-dir might be different for the repo you are working in. Ask a team lead about it if you need help.