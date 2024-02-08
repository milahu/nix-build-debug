# nix-shell



## nix-build.cc

the old `nix-shell` is in [nix/src/nix-build/nix-build.cc](https://github.com/NixOS/nix/blob/master/src/nix-build/nix-build.cc)

`runEnv == true` for nix-shell

```cc
static void main_nix_build(int argc, char * * argv)
{
    auto dryRun = false;
    auto runEnv = std::regex_search(argv[0], std::regex("nix-shell$"));



    MyArgs myArgs(myName, [&](Strings::iterator & arg, const Strings::iterator & end) {

        else if (*arg == "--attr" || *arg == "-A")
            attrPaths.push_back(getArg(*arg, arg, end));

        else
            left.push_back(*arg);



    if (packages) {
        std::ostringstream joined;
        joined << "{...}@args: with import <nixpkgs> args; (pkgs.runCommandCC or pkgs.runCommand) \"shell\" { buildInputs = [ ";
        for (const auto & i : left)
            joined << '(' << i << ") ";
        joined << "]; } \"\"";
        fromArgs = true;
        left = {joined.str()};
    } else if (!fromArgs) {
        if (left.empty() && runEnv && pathExists("shell.nix"))
            left = {"shell.nix"};
        if (left.empty())
            left = {"default.nix"};
    }



    if (runEnv)
        setenv("IN_NIX_SHELL", pure ? "pure" : "impure", 1);



            store->buildPaths(paths, buildMode, evalStore);



    if (runEnv) {
        if (drvs.size() != 1)
            throw UsageError("nix-shell requires a single derivation");


        auto & packageInfo = drvs.front();
        auto drv = evalStore->derivationFromPath(packageInfo.requireDrvPath());


        auto shell = getEnv("NIX_BUILD_SHELL");
        if (!shell) {
            try {
                auto expr = state->parseExprFromString(
                    "(import <nixpkgs> {}).bashInteractive",
                    state->rootPath(CanonPath::fromCwd()));
```

```
$ nix-build '<nixpkgs>' -A bashInteractive
/nix/store/iqmric18ds75hg8v7yjdl2xkydfnahdy-bash-interactive-5.2-p21

nix-build-debug $ echo $builder
/nix/store/9vafkkic27k7m4934fpawl6yip3a6k4h-bash-5.2-p21/bin/bash
```

```
        auto passAsFile = tokenizeString<StringSet>(getOr(drv.env, "passAsFile", ""));

        bool keepTmp = false;
        int fileNr = 0;

        for (auto & var : drv.env)
            if (passAsFile.count(var.first)) {
                keepTmp = true;
                auto fn = ".attr-" + std::to_string(fileNr++);
                Path p = (Path) tmpDir + "/" + fn;
                writeFile(p, var.second);
                env[var.first + "Path"] = p;
            } else
                env[var.first] = var.second;

        std::string structuredAttrsRC;

        if (env.count("__json")) {

                auto attrsJSON = (Path) tmpDir + "/.attrs.json";
                writeFile(attrsJSON, json.dump());

                auto attrsSH = (Path) tmpDir + "/.attrs.sh";
                writeFile(attrsSH, structuredAttrsRC);
```


```
        /* Run a shell using the derivation's environment.  For
           convenience, source $stdenv/setup to setup additional
           environment variables and shell functions.  Also don't
           lose the current $PATH directories. */
        auto rcfile = (Path) tmpDir + "/rc";
        std::string rc = fmt(
                R"(_nix_shell_clean_tmpdir() { command rm -rf %1%; }; )"s +
                (keepTmp ?
                    "trap _nix_shell_clean_tmpdir EXIT; "
                    "exitHooks+=(_nix_shell_clean_tmpdir); "
                    "failureHooks+=(_nix_shell_clean_tmpdir); ":
                    "_nix_shell_clean_tmpdir; ") +
                (pure ? "" : "[ -n \"$PS1\" ] && [ -e ~/.bashrc ] && source ~/.bashrc;") +
                "%2%"
                // always clear PATH.
                // when nix-shell is run impure, we rehydrate it with the `p=$PATH` above
                "unset PATH;"
                "dontAddDisableDepTrack=1;\n"
                + structuredAttrsRC +
                "\n[ -e $stdenv/setup ] && source $stdenv/setup; "
                "%3%"
                "PATH=%4%:\"$PATH\"; "
                "SHELL=%5%; "
                "BASH=%5%; "
                "set +e; "
                R"s([ -n "$PS1" -a -z "$NIX_SHELL_PRESERVE_PROMPT" ] && )s" +
                (getuid() == 0 ? R"s(PS1='\n\[\033[1;31m\][nix-shell:\w]\$\[\033[0m\] '; )s"
                               : R"s(PS1='\n\[\033[1;32m\][nix-shell:\w]\$\[\033[0m\] '; )s") +
                "if [ \"$(type -t runHook)\" = function ]; then runHook shellHook; fi; "
                "unset NIX_ENFORCE_PURITY; "
                "shopt -u nullglob; "
                "unset TZ; %6%"
                "shopt -s execfail;"
                "%7%",
                shellEscape(tmpDir),
                (pure ? "" : "p=$PATH; "),
                (pure ? "" : "PATH=$PATH:$p; unset p; "),
                shellEscape(dirOf(*shell)),
                shellEscape(*shell),
                (getenv("TZ") ? (std::string("export TZ=") + shellEscape(getenv("TZ")) + "; ") : ""),
                envCommand);
        vomit("Sourcing nix-shell with file %s and contents:\n%s", rcfile, rc);
        writeFile(rcfile, rc);

        Strings envStrs;
        for (auto & i : env)
            envStrs.push_back(i.first + "=" + i.second);

        auto args = interactive
            ? Strings{"bash", "--rcfile", rcfile}
            : Strings{"bash", rcfile};

        auto envPtrs = stringsToCharPtrs(envStrs);

        environ = envPtrs.data();

        auto argPtrs = stringsToCharPtrs(args);

        restoreProcessContext();

        logger->stop();

        execvp(shell->c_str(), argPtrs.data());
```



## develop.cc

`nix develop` is the new version of `nix-shell`

https://github.com/NixOS/nix/blob/master/src/nix/develop.cc

```
Given an existing derivation, return the shell environment as
initialised by stdenv's setup script. We do this by building a
modified derivation with the same dependencies and nearly the same
initial environment variables, that just writes the resulting
environment to a file and exits.
```

```cc
Path shell = "bash";
auto [rcFileFd, rcFilePath] = createTempFile("nix-shell");
auto script = makeRcScript(store, buildEnvironment);
writeFull(rcFileFd.get(), script);
auto args = phase || !command.empty() ? Strings{std::string(baseNameOf(shell)), rcFilePath}
    : Strings{std::string(baseNameOf(shell)), "--rcfile", rcFilePath};
runProgramInStore(store, shell, args);
```



### env.json

```cc
static StorePath getDerivationEnvironment(ref<Store> store, ref<Store> evalStore, const StorePath & drvPath)
drv.name += "-env";
auto getEnvShPath = evalStore->addTextToStore("get-env.sh", getEnvSh, {});
drv.inputSrcs.insert(std::move(getEnvShPath));
return outPath;
```

`get-env.sh` writes a json file to `$out`

the `env.json` file looks like

```json
{
  "bashFunctions": {
    "_accumFlagsArray":"..."
    ...
  },
  "variables": {
    "CC": {"type": "exported", "value": "gcc"},
    "builder": {"type": "exported", "value": "/nix/store/9vafkkic27k7m4934fpawl6yip3a6k4h-bash-5.2-p21/bin/bash"},
    "outputBin": {"type": "var", "value": "out"},
    "pkgsHostHost": {"type": "array", "value": []},
    "preConfigurePhases": {"type": "var", "value": " updateAutotoolsGnuConfigScriptsPhase updateAutotoolsGnuConfigScriptsPhase"},
    "prefix": {"type": "var", "value": "/nix/store/xmccz9w8wqks0kvs8jcwpyg8hswc4ga7-hello-2.12.1"},
    "test_assoc": {"type": "associative", "value": {
      "key": "val"
    }},
    ...
  }
}
```

the `env.json` file is parsed in


```cc
static BuildEnvironment fromJSON(std::string_view in)
{
    BuildEnvironment res;

    for (auto & [name, info] : json["variables"].items()) {
        std::string type = info["type"];
        if (type == "var" || type == "exported")
            res.vars.insert({name, BuildEnvironment::String { .exported = type == "exported", .value = info["value"] }});
        else if (type == "array")
            res.vars.insert({name, (Array) info["value"]});
        else if (type == "associative")
            res.vars.insert({name, (Associative) info["value"]});
    }

    for (auto & [name, def] : json["bashFunctions"].items()) {
        res.bashFunctions.insert({name, def});
    }

    return res;
}
```

later this `buildEnvironment` is used to create the rcfile for bash

```
buildEnvironment.toBash(out, ignoreVars);
```

```cc
void toBash(std::ostream & out, const std::set<std::string> & ignoreVars) const
{
    for (auto & [name, value] : vars) {
        if (!ignoreVars.count(name)) {
            if (auto str = std::get_if<String>(&value)) {
                out << fmt("%s=%s\n", name, shellEscape(str->value));
                if (str->exported)
                    out << fmt("export %s\n", name);
            }
            else if (auto arr = std::get_if<Array>(&value)) {
                out << "declare -a " << name << "=(";
                for (auto & s : *arr)
                    out << shellEscape(s) << " ";
                out << ")\n";
            }
            else if (auto arr = std::get_if<Associative>(&value)) {
                out << "declare -A " << name << "=(";
                for (auto & [n, v] : *arr)
                    out << "[" << shellEscape(n) << "]=" << shellEscape(v) << " ";
                out << ")\n";
            }
        }
    }
    for (auto & [name, def] : bashFunctions) {
        out << name << " ()\n{\n" << def << "}\n";
    }
}
```



## rcfile

```sh
nix-shell '<nixpkgs>' -A hello
```

runs

```sh
bash --rcfile /tmp/nix-shell-273480-0/rc
```

but the rcfile is deleted after the shell has started

```cc
script += fmt("command rm -f '%s'\n", rcFilePath);
```
