# nix-shell



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
